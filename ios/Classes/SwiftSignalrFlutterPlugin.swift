import Flutter
import UIKit

public class SwiftSignalrFlutterPlugin: NSObject, FlutterPlugin, FLTSignalRHostApi {
  private static var signalrApi : FLTSignalRPlatformApi?

  private var hub: Hub?
  private var connection: SignalR?

  /// Completion of the `connect`/`reconnect` call that is currently waiting for the
  /// connection to come up. Completed exactly once by the connection callbacks.
  private var pendingStart: ((String?, FlutterError?) -> Void)?
  private var lastErrorMessage: String?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let messenger : FlutterBinaryMessenger = registrar.messenger()
    let instance = SwiftSignalrFlutterPlugin.init()
    FLTSignalRHostApiSetup(messenger, instance)
    signalrApi = FLTSignalRPlatformApi.init(binaryMessenger: messenger)
    // Publishing makes the engine call `detachFromEngine(for:)` so the connection is released.
    registrar.publish(instance)
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    let messenger : FlutterBinaryMessenger = registrar.messenger()
    FLTSignalRHostApiSetup(messenger, nil)
    SwiftSignalrFlutterPlugin.signalrApi = nil
    tearDownConnection()
  }

  public func connect(_ connectionOptions: FLTConnectionOptions?, completion: @escaping (String?, FlutterError?) -> Void) {
    guard let options = connectionOptions else {
      completion(nil, FlutterError(code: "platform-error", message: "Connection options have null value", details: nil))
      return
    }

    guard let hubName = options.hubName, !hubName.isEmpty else {
      completion(nil, FlutterError(code: "platform-error", message: "Hub name have null value", details: nil))
      return
    }

    // Drop any previous connection so its (late) callbacks can't clobber the new one's state.
    tearDownConnection()

    let connection = SignalR(options.baseUrl ?? "")
    self.connection = connection

    if let queryString = options.queryString, !queryString.isEmpty {
      // Passed through verbatim (same as Android) so multiple parameters and
      // pre-encoded values work.
      connection.queryString = queryString
    }

    switch options.transport {
    case .longPolling:
      connection.transport = Transport.longPolling
    case .serverSentEvents:
      connection.transport = Transport.serverSentEvents
    case .auto:
      connection.transport = Transport.auto
    @unknown default:
      break
    }

    if let headers = options.headers, !headers.isEmpty {
      connection.headers = headers
    }

    let hub = connection.createHubProxy(hubName)
    self.hub = hub

    if let hubMethods = options.hubMethods, !hubMethods.isEmpty {
      hubMethods.forEach { (methodName) in
        hub.on(methodName) { (args) in
          let message = SwiftSignalrFlutterPlugin.stringify(arguments: args)
          SwiftSignalrFlutterPlugin.signalrApi?.onNewMessageHubName(methodName, message: message, completion: { error in })
        }
      }
    }

    connection.starting = { [weak self] in
      self?.postStatusChange(.connecting, connectionId: nil)
    }

    connection.reconnecting = { [weak self] in
      self?.postStatusChange(.reconnecting, connectionId: nil)
    }

    connection.connected = { [weak self] in
      guard let self = self else { return }
      self.postStatusChange(.connected, connectionId: connection.connectionID)
      self.finishStart(connection.connectionID, nil)
    }

    connection.reconnected = { [weak self] in
      guard let self = self else { return }
      self.postStatusChange(.connected, connectionId: connection.connectionID)
      self.finishStart(connection.connectionID, nil)
    }

    connection.disconnected = { [weak self] in
      guard let self = self else { return }
      self.postStatusChange(.disconnected, connectionId: connection.connectionID)
      self.finishStart(nil, self.startError("Connection closed before it was established"))
    }

    connection.connectionFailed = { [weak self] in
      guard let self = self else { return }
      self.finishStart(nil, self.startError("Connection failed"))
    }

    connection.connectionSlow = { [weak self] in
      self?.postStatusChange(.connectionSlow, connectionId: connection.connectionID)
    }

    connection.error = { [weak self] error in
      guard let self = self else { return }
      let message = (error?["message"] as? String) ?? error?.description ?? "An unknown error has occurred."
      print("SignalR Error: \(message)")
      self.lastErrorMessage = message
      self.postStatusChange(.connectionError, connectionId: nil, errorMessage: message)
    }

    startConnection(connection, completion: completion)
  }

  public func reconnect(completion: @escaping (String?, FlutterError?) -> Void) {
    guard let connection = self.connection else {
      completion(nil, FlutterError(code: "platform-error", message: "SignalR Connection not found or null", details: "Start SignalR connection first"))
      return
    }

    if connection.state == .connected {
      completion(connection.connectionID ?? "", nil)
      return
    }

    startConnection(connection, completion: completion)
  }

  public func stop(completion: @escaping (FlutterError?) -> Void) {
    connection?.stop()
    completion(nil)
  }

  public func isConnected(completion: @escaping (NSNumber?, FlutterError?) -> Void) {
    if let connection = self.connection {
      switch connection.state {
      case .connected:
        completion(true, nil)
      default:
        completion(false, nil)
      }
    } else {
      completion(false, nil)
    }
  }

  public func invokeMethodMethodName(_ methodName: String?, arguments: [String]?, completion: @escaping (String?, FlutterError?) -> Void) {
    do {
      guard let hub = self.hub else {
        throw NSError.init(domain: "NullPointerException", code: 0, userInfo: [NSLocalizedDescriptionKey : "Hub is null. Initiate a connection first."])
      }
      guard let methodName = methodName, !methodName.isEmpty else {
        throw NSError.init(domain: "IllegalArgumentException", code: 0, userInfo: [NSLocalizedDescriptionKey : "Method name have null value"])
      }

      try hub.invoke(methodName, arguments: arguments, callback: { (res, error) in
        if let error = error {
          let message = ((error as? [String: Any])?["message"] as? String) ?? String(describing: error)
          completion(nil, FlutterError(code: "platform-error", message: message, details: nil))
        } else {
          completion(SwiftSignalrFlutterPlugin.stringify(res), nil)
        }
      })
    } catch let error as SwiftRError {
      completion(nil, FlutterError.init(code: "platform-error", message: error.message, details: nil))
    } catch {
      completion(nil ,FlutterError.init(code: "platform-error", message: error.localizedDescription, details: nil))
    }
  }

  // MARK: - Helpers

  private func startConnection(_ connection: SignalR, completion: @escaping (String?, FlutterError?) -> Void) {
    // A start that is still pending is superseded by this one.
    finishStart(nil, FlutterError(code: "platform-error", message: "Superseded by a newer connection attempt", details: nil))
    lastErrorMessage = nil
    pendingStart = completion
    connection.start()
  }

  private func finishStart(_ connectionId: String?, _ error: FlutterError?) {
    guard let completion = pendingStart else { return }
    pendingStart = nil
    completion(connectionId ?? "", error)
  }

  private func startError(_ fallback: String) -> FlutterError {
    return FlutterError(code: "connection-error", message: lastErrorMessage ?? fallback, details: nil)
  }

  private func tearDownConnection() {
    finishStart(nil, FlutterError(code: "platform-error", message: "Connection was torn down", details: nil))
    connection?.tearDown()
    connection = nil
    hub = nil
  }

  private func postStatusChange(_ status: FLTConnectionStatus, connectionId: String?, errorMessage: String? = nil) {
    let statusChangeResult : FLTStatusChangeResult = FLTStatusChangeResult.init()
    statusChangeResult.connectionId = connectionId
    statusChangeResult.status = status
    statusChangeResult.errorMessage = errorMessage
    SwiftSignalrFlutterPlugin.signalrApi?.onStatusChange(statusChangeResult, completion: { error in })
  }

  /// A plain string is forwarded as-is; anything else is forwarded as JSON.
  private static func stringify(_ value: Any?) -> String {
    guard let value = value, !(value is NSNull) else { return "" }
    if let string = value as? String { return string }
    return SignalR.stringify(value) ?? String(describing: value)
  }

  /// Single argument -> the argument itself, multiple arguments -> a JSON array of them.
  private static func stringify(arguments: [Any]?) -> String {
    guard let arguments = arguments, !arguments.isEmpty else { return "" }
    if arguments.count == 1 { return stringify(arguments[0]) }
    return SignalR.stringify(arguments) ?? ""
  }
}
