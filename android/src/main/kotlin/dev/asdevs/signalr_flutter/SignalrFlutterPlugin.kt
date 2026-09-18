package dev.asdevs.signalr_flutter

import android.os.Handler
import android.os.Looper
import androidx.annotation.NonNull
import com.google.gson.JsonArray
import com.google.gson.JsonElement

import io.flutter.embedding.engine.plugins.FlutterPlugin
import microsoft.aspnet.signalr.client.ConnectionState
import microsoft.aspnet.signalr.client.Credentials
import microsoft.aspnet.signalr.client.LogLevel
import microsoft.aspnet.signalr.client.SignalRFuture
import microsoft.aspnet.signalr.client.hubs.HubConnection
import microsoft.aspnet.signalr.client.hubs.HubProxy
import microsoft.aspnet.signalr.client.transport.LongPollingTransport
import microsoft.aspnet.signalr.client.transport.ServerSentEventsTransport
import java.util.concurrent.atomic.AtomicBoolean

/** SignalrFlutterPlugin */
class SignalrFlutterPlugin : FlutterPlugin, SignalrApi.SignalRHostApi {
    private lateinit var connection: HubConnection
    private lateinit var hub: HubProxy

    private lateinit var signalrApi: SignalrApi.SignalRPlatformApi

    // Pigeon replies and Flutter API calls must happen on the platform (main) thread,
    // while the SignalR SDK invokes its callbacks from background threads.
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        SignalrApi.SignalRHostApi.setup(flutterPluginBinding.binaryMessenger, this)
        signalrApi = SignalrApi.SignalRPlatformApi(flutterPluginBinding.binaryMessenger)
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        SignalrApi.SignalRHostApi.setup(binding.binaryMessenger, null)
        stopConnection(detachCallbacks = true)
    }

    override fun connect(
        connectionOptions: SignalrApi.ConnectionOptions?,
        result: SignalrApi.Result<String>?
    ) {
        try {
            connectionOptions ?: throw NullPointerException("Connection options have null value")

            // Drop any previous connection so its (late) callbacks can't clobber the new one's state.
            stopConnection(detachCallbacks = true)

            val conn =
                if (connectionOptions.queryString != null && connectionOptions.queryString.isNotEmpty()) {
                    HubConnection(
                        connectionOptions.baseUrl,
                        connectionOptions.queryString,
                        true
                    ) { _: String, _: LogLevel ->
                    }
                } else {
                    HubConnection(connectionOptions.baseUrl)
                }

            if (connectionOptions.headers != null && connectionOptions.headers.isNotEmpty()) {
                val cred = Credentials { request ->
                    request.headers = connectionOptions.headers
                }
                conn.credentials = cred
            }

            val hubProxy = conn.createHubProxy(connectionOptions.hubName)

            connectionOptions.hubMethods?.forEach { methodName ->
                // Subscribe to the raw JsonElement arguments instead of the typed `on(..., String::class.java)`
                // overload: the typed overload throws when the server sends a different number of
                // arguments or a non-string payload.
                hubProxy.subscribe(methodName).addReceivedHandler { args ->
                    val message = argumentsToString(args)
                    mainHandler.post {
                        signalrApi.onNewMessage(methodName, message) { }
                    }
                }
            }

            conn.connected {
                postStatusChange(SignalrApi.ConnectionStatus.connected, conn.connectionId)
            }

            conn.reconnected {
                postStatusChange(SignalrApi.ConnectionStatus.connected, conn.connectionId)
            }

            conn.reconnecting {
                postStatusChange(SignalrApi.ConnectionStatus.reconnecting, conn.connectionId)
            }

            conn.closed {
                postStatusChange(SignalrApi.ConnectionStatus.disconnected, conn.connectionId)
            }

            conn.connectionSlow {
                postStatusChange(SignalrApi.ConnectionStatus.connectionSlow, conn.connectionId)
            }

            conn.error { throwable ->
                postStatusChange(
                    SignalrApi.ConnectionStatus.connectionError,
                    null,
                    throwable.localizedMessage ?: throwable.toString()
                )
            }

            connection = conn
            hub = hubProxy

            val startFuture = when (connectionOptions.transport) {
                SignalrApi.Transport.serverSentEvents -> conn.start(
                    ServerSentEventsTransport(
                        conn.logger
                    )
                )
                SignalrApi.Transport.longPolling -> conn.start(LongPollingTransport(conn.logger))
                else -> {
                    conn.start()
                }
            }

            replyWhenStarted(conn, startFuture, result)
        } catch (ex: Exception) {
            result?.error(ex)
        }
    }

    override fun reconnect(result: SignalrApi.Result<String>?) {
        try {
            if (!this::connection.isInitialized) {
                throw IllegalStateException("SignalR Connection not found or null. Start SignalR connection first.")
            }
            replyWhenStarted(connection, connection.start(), result)
        } catch (ex: Exception) {
            result?.error(ex)
        }
    }

    override fun stop(result: SignalrApi.Result<Void>?) {
        try {
            stopConnection()
            result?.success(null)
        } catch (ex: Exception) {
            result?.error(ex)
        }
    }

    override fun isConnected(result: SignalrApi.Result<Boolean>?) {
        try {
            if (this::connection.isInitialized) {
                when (connection.state) {
                    ConnectionState.Connected -> result?.success(true)
                    else -> result?.success(false)
                }
            } else {
                result?.success(false)
            }
        } catch (ex: Exception) {
            result?.error(ex)
        }
    }

    override fun invokeMethod(
        methodName: String?,
        arguments: MutableList<String>?,
        result: SignalrApi.Result<String>?
    ) {
        try {
            arguments ?: throw NullPointerException("Arguments have null value")
            if (!this::hub.isInitialized) {
                throw IllegalStateException("Hub is null. Initiate a connection first.")
            }

            // Ask for the raw JsonElement so non-string return values (objects, numbers, arrays)
            // are forwarded as JSON instead of failing gson deserialization.
            val res: SignalRFuture<JsonElement> =
                hub.invoke(JsonElement::class.java, methodName, *arguments.toTypedArray())

            val replied = AtomicBoolean(false)

            res.done { msg: JsonElement? ->
                if (replied.compareAndSet(false, true)) {
                    val message = jsonToString(msg)
                    mainHandler.post { result?.success(message) }
                }
            }

            res.onError { throwable ->
                if (replied.compareAndSet(false, true)) {
                    mainHandler.post { result?.error(throwable) }
                }
            }
        } catch (ex: Exception) {
            result?.error(ex)
        }
    }

    //---- Helpers ----//

    /** Completes [result] with the connection id once [startFuture] finishes (or fails). */
    private fun replyWhenStarted(
        conn: HubConnection,
        startFuture: SignalRFuture<Void>,
        result: SignalrApi.Result<String>?
    ) {
        val replied = AtomicBoolean(false)

        startFuture.done {
            if (replied.compareAndSet(false, true)) {
                val connectionId = conn.connectionId ?: ""
                mainHandler.post { result?.success(connectionId) }
            }
        }

        startFuture.onError { throwable ->
            if (replied.compareAndSet(false, true)) {
                mainHandler.post { result?.error(throwable) }
            }
        }
    }

    private fun stopConnection(detachCallbacks: Boolean = false) {
        if (!this::connection.isInitialized) return

        val conn = connection
        if (detachCallbacks) {
            conn.connected(null)
            conn.reconnected(null)
            conn.reconnecting(null)
            conn.connectionSlow(null)
            conn.error(null)
            conn.closed(null)
        }
        conn.stop()
    }

    private fun postStatusChange(
        status: SignalrApi.ConnectionStatus,
        connectionId: String?,
        errorMessage: String? = null
    ) {
        if (!this::signalrApi.isInitialized) return

        mainHandler.post {
            val statusChangeResult = SignalrApi.StatusChangeResult()
            statusChangeResult.connectionId = connectionId
            statusChangeResult.status = status
            statusChangeResult.errorMessage = errorMessage
            signalrApi.onStatusChange(statusChangeResult) { }
        }
    }

    /** A plain string is forwarded as-is; anything else is forwarded as JSON. */
    private fun jsonToString(element: JsonElement?): String = when {
        element == null || element.isJsonNull -> ""
        element.isJsonPrimitive && element.asJsonPrimitive.isString -> element.asString
        else -> element.toString()
    }

    /** Single argument -> the argument itself, multiple arguments -> a JSON array of them. */
    private fun argumentsToString(args: Array<JsonElement>?): String = when {
        args == null || args.isEmpty() -> ""
        args.size == 1 -> jsonToString(args[0])
        else -> JsonArray().apply { args.forEach { add(it) } }.toString()
    }
}
