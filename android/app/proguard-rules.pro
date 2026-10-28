# Plugins built on package:jni (e.g. shared_preferences_android) look these
# classes up from Dart by name, so R8 must not strip or rename them; otherwise
# the release app crashes at startup and shows a blank screen.
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class com.github.dart_lang.jni.** { *; }
-keep class kotlin.coroutines.** { *; }
-keep class kotlinx.coroutines.** { *; }
-keep class kotlin.jvm.functions.** { *; }
-keep class kotlin.Unit { *; }
-keep class kotlin.Result { *; }
-keep class kotlin.Result$* { *; }
