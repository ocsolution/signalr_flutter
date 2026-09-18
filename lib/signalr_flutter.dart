import 'dart:async';

import 'package:signalr_flutter/signalr_api.dart';
import 'package:signalr_flutter/signalr_platform_interface.dart';

export 'package:signalr_flutter/signalr_api.dart' show Transport, ConnectionStatus;

class SignalR extends SignalrPlatformInterface implements SignalRPlatformApi {
  // Private variables
  static final SignalRHostApi _signalrApi = SignalRHostApi();

  // Constructor
  SignalR(
    String baseUrl,
    String hubName, {
    String? queryString,
    Map<String, String>? headers,
    List<String>? hubMethods,
    Transport transport = Transport.auto,
    void Function(ConnectionStatus?)? statusChangeCallback,
    void Function(String, String)? hubCallback,
  }) : super(baseUrl, hubName,
            queryString: queryString,
            headers: headers,
            hubMethods: hubMethods,
            transport: transport,
            statusChangeCallback: statusChangeCallback,
            hubCallback: hubCallback);

  //---- Callback Methods ----//
  // ------------------------//
  @override
  Future<void> onNewMessage(String hubName, String message) async {
    hubCallback?.call(hubName, message);
  }

  @override
  Future<void> onStatusChange(StatusChangeResult statusChangeResult) async {
    // Transient errors (e.g. while reconnecting) don't carry a connection id,
    // so only overwrite the one we have when the platform actually sends one.
    if (statusChangeResult.connectionId != null) {
      connectionId = statusChangeResult.connectionId;
    } else if (statusChangeResult.status == ConnectionStatus.disconnected) {
      connectionId = null;
    }

    if (statusChangeResult.errorMessage != null) {
      lastErrorMessage = statusChangeResult.errorMessage;
    }

    statusChangeCallback?.call(statusChangeResult.status);
  }

  //---- Public Methods ----//
  // ------------------------//

  /// Connect to the SignalR Server with given [baseUrl] & [hubName].
  ///
  /// [queryString] is a optional field to send query to server.
  ///
  /// Returns the [connectionId].
  @override
  Future<String?> connect() async {
    // Construct ConnectionOptions
    ConnectionOptions options = ConnectionOptions();
    options.baseUrl = baseUrl;
    options.hubName = hubName;
    options.queryString = queryString;
    options.hubMethods = hubMethods;
    options.headers = headers;
    options.transport = transport;

    // Register SignalR Callbacks
    SignalRPlatformApi.setup(this);

    connectionId = await _signalrApi.connect(options);

    return connectionId;
  }

  /// Try to Reconnect SignalR connection if it gets disconnected.
  ///
  /// Returns the [connectionId]
  @override
  Future<String?> reconnect() async {
    connectionId = await _signalrApi.reconnect();
    return connectionId;
  }

  /// Stops SignalR connection
  @override
  Future<void> stop() => _signalrApi.stop();

  /// Checks if SignalR connection is still active.
  ///
  /// Returns a boolean value
  @override
  Future<bool> isConnected() => _signalrApi.isConnected();

  /// Invoke any server method with optional [arguments].
  @override
  Future<String> invokeMethod(String methodName, {List<String>? arguments}) =>
      _signalrApi.invokeMethod(methodName, arguments ?? const <String>[]);
}
