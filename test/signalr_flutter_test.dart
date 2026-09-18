import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalr_flutter/signalr_api.dart';
import 'package:signalr_flutter/signalr_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String channelPrefix = 'dev.flutter.pigeon.SignalRHostApi.';

  /// Records every host-api call and answers each with the value from [replies].
  final List<MapEntry<String, Object?>> calls = <MapEntry<String, Object?>>[];
  final Map<String, Object?> replies = <String, Object?>{};

  void mockHost(String method) {
    final BasicMessageChannel<Object?> channel =
        BasicMessageChannel<Object?>('$channelPrefix$method', SignalRHostApi.codec);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(channel, (Object? message) async {
      calls.add(MapEntry<String, Object?>(method, message));
      return <Object?, Object?>{'result': replies[method]};
    });
  }

  setUp(() {
    calls.clear();
    replies.clear();
    for (final String method in <String>['connect', 'reconnect', 'stop', 'isConnected', 'invokeMethod']) {
      mockHost(method);
    }
  });

  test('connect forwards all options, including transport, and stores the connection id', () async {
    replies['connect'] = 'conn-1';
    final SignalR signalR = SignalR(
      'https://example.com',
      'chatHub',
      queryString: 'a=1&b=2',
      headers: <String, String>{'Authorization': 'Bearer x'},
      hubMethods: <String>['broadcast'],
      transport: Transport.longPolling,
    );

    expect(await signalR.connect(), 'conn-1');
    expect(signalR.connectionId, 'conn-1');

    expect(calls, hasLength(1));
    final List<Object?> args = calls.single.value! as List<Object?>;
    final ConnectionOptions options = args[0]! as ConnectionOptions;
    expect(options.baseUrl, 'https://example.com');
    expect(options.hubName, 'chatHub');
    expect(options.queryString, 'a=1&b=2');
    expect(options.headers, <String, String>{'Authorization': 'Bearer x'});
    expect(options.hubMethods, <String>['broadcast']);
    expect(options.transport, Transport.longPolling);
  });

  test('stop completes', () async {
    final SignalR signalR = SignalR('https://example.com', 'chatHub');
    await expectLater(signalR.stop(), completes);
    expect(calls.single.key, 'stop');
  });

  test('invokeMethod sends an empty argument list by default', () async {
    replies['invokeMethod'] = '42';
    final SignalR signalR = SignalR('https://example.com', 'chatHub');

    expect(await signalR.invokeMethod('Add'), '42');
    expect(calls.single.value, <Object?>['Add', <String>[]]);
  });

  test('host api errors surface as PlatformException', () async {
    const BasicMessageChannel<Object?> channel =
        BasicMessageChannel<Object?>('${channelPrefix}connect', SignalRHostApi.codec);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(channel, (Object? message) async {
      return <Object?, Object?>{
        'error': <Object?, Object?>{'code': 'connection-error', 'message': 'refused'}
      };
    });
    final SignalR signalR = SignalR('https://example.com', 'chatHub');

    await expectLater(
      signalR.connect(),
      throwsA(isA<PlatformException>().having((PlatformException e) => e.message, 'message', 'refused')),
    );
  });

  test('onStatusChange reports errors through the callback without throwing', () async {
    final List<ConnectionStatus?> statuses = <ConnectionStatus?>[];
    final SignalR signalR = SignalR(
      'https://example.com',
      'chatHub',
      statusChangeCallback: statuses.add,
    );

    await signalR.onStatusChange(StatusChangeResult()
      ..status = ConnectionStatus.connected
      ..connectionId = 'conn-1');
    await signalR.onStatusChange(StatusChangeResult()
      ..status = ConnectionStatus.connectionError
      ..errorMessage = 'boom');

    expect(statuses, <ConnectionStatus>[ConnectionStatus.connected, ConnectionStatus.connectionError]);
    // A transient error must not wipe the id of a still-open connection.
    expect(signalR.connectionId, 'conn-1');
    expect(signalR.lastErrorMessage, 'boom');

    await signalR.onStatusChange(StatusChangeResult()..status = ConnectionStatus.disconnected);
    expect(signalR.connectionId, isNull);
  });

  test('onNewMessage forwards to hubCallback', () async {
    final List<String> received = <String>[];
    final SignalR signalR = SignalR(
      'https://example.com',
      'chatHub',
      hubCallback: (String method, String message) => received.add('$method:$message'),
    );

    await signalR.onNewMessage('broadcast', 'hello');
    expect(received, <String>['broadcast:hello']);
  });
}
