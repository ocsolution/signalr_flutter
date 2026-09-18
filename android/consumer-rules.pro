# The SignalR Java client deserializes its protocol messages with Gson (reflection),
# so R8 must not strip or rename any of its classes in consumer release builds.
-keep class microsoft.aspnet.signalr.client.** { *; }
-keepattributes Signature, *Annotation*
-dontwarn microsoft.aspnet.signalr.client.**
