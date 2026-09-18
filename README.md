# signalr_flutter

A flutter plugin for .net SignalR client.

## Usage

First of all, Initialize SignalR and connect to your server.

```dart
SignalR signalR = SignalR(
        '<Your server url here>',
        "<Your hub name here>",
        hubMethods: ["<Your Hub Method Names>"],
        statusChangeCallback: (status) => print(status),
        hubCallback: (methodName, message) => print('MethodName = $methodName, Message = $message'));
final connectionId = await signalR.connect();
```

`connect()` completes once the connection is established and returns the connection id; it throws a `PlatformException` if the connection fails. Call `await signalR.stop()` to disconnect.

Here `statusChangeCallback` will get called whenever connection status with server changes. When the status is `ConnectionStatus.connectionError`, the error text is available in `signalR.lastErrorMessage`.

`hubCallback` will receive calls from the server if you subscribe to any hub method. You can do that with `hubMethods`. A single string argument is delivered as-is; any other payload (objects, arrays, numbers, or multiple arguments) is delivered as a JSON string.

`hubMethods` are the hub method names you want to subscribe.

There is a `headers` parameters also which takes a `Map<String, String>`.

You can also invoke any server method.

```dart
signalR.invokeMethod("<Your method name here>", arguments: ["argument1", "argument2"]);
```


If you are trying to connect with a HTTP url, then you need to add the following lines to the manifest of your android project.

```xml
<application
        android:usesCleartextTraffic="true">
</application>
```

This is because of the [Network Security Config](https://developer.android.com/training/articles/security-config#CleartextTrafficPermitted).

The plugin ships the R8/ProGuard keep rules the SignalR Android client needs, so release builds work without extra configuration. If you use a custom shrinker setup that ignores consumer rules, add:

`-keep class microsoft.aspnet.signalr.client.** { *; }`


For more info check example.

Any issue or PR is always welcome.

