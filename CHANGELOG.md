## 0.0.1

* Initial release.

## 0.0.2

* Minor Updates.

## 0.0.3

* Connection Headers and Transport customization added
* Minor changes and a bug fix for invokeServerMethod

## 0.0.4

* Minor Updates.

## 0.0.5

* Fixed a bug where invokeMethod only accepting string as return value

## 0.0.6-dev.1

* Possible fix for callbacks throwing exception about type mismatch.
* invokeMethod now has generic return type & upto 10 arguments support.

## 0.0.6-dev.2

* HubCallBack function now returns the value as well as the subscribed method name.
* invokeMethod now can take as many arguments as you want.

## 0.0.6-dev.3

* Possible fix for ios Hub events not returning

## 0.1.0-dev.1

* Fix for ios Hub events not returning

## 0.1.0-dev.2

* Fixed Duplicated Hub events for ios.

## 0.1.0

* Fix a issue where hub callback only accepting strings.
* Hub callback now returns the message as well as the subscribed method name.
* Made invokeMethod generic.
* As many arguments as you want in invokeMethod.
* fix for ios Hub events not working.

## 0.1.1

* Null Safety Support

## 0.1.2

* IsConnected Method Added

## 0.2.0-dev.1

* Rewrote the plugin using pigeon
* **Breaking Changes**: 
    * `invokeMethod` now take only strings as arguments instead of dynamic.
    * `invokeMethod` now returns only string as result.
    * `hubCallback` now also returns string as message instead of dynamic.

## 0.2.0-dev.2

* Fix for invokeMethod calls having no return value.

## 0.2.0-dev.3

* Updated signalr for iOS.
* Transport fallback properly added for iOS.

## 0.2.0-dev.4

* App bundle build issue fix.

## 0.2.0-dev.5

* `transport` passed to the `SignalR` constructor is now actually used (it was silently ignored before).
* `stop()` now returns a `Future<void>` that completes; previously the native side never replied, so awaiting it hung forever.
* `connect()`/`reconnect()` now resolve once the connection is actually established and return the real `connectionId` (they used to return an empty string immediately). Connection failures reject the future.
* Connection errors no longer throw an unhandled `PlatformException` out of the status callback; the message is available on `lastErrorMessage` alongside `ConnectionStatus.connectionError`.
* Android: `invokeMethod` failures are reported to the caller instead of throwing on a background thread.
* Android & iOS: hub messages and `invokeMethod` results that are not plain strings (objects, arrays, numbers, multiple arguments) are delivered as JSON instead of crashing / being dropped.
* iOS: `queryString` with several parameters (`a=1&b=2`) or without `=` no longer crashes; it is passed through verbatim like on Android.
* iOS: calling `connect()` again tears down the previous connection (and its `WKWebView`) instead of leaking it.
* Android: R8 keep rules for the SignalR client are now shipped with the plugin (`consumer-rules.pro`), so no manual proguard entry is needed.
* Example app updated to current Flutter / Android Gradle tooling.

