# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Firebase
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes EnclosingMethod
-keep class com.google.firebase.** { *; }

# Just Audio
-keep class com.ryanheise.** { *; }

# Prevent obfuscation of some essential classes
-keep class * extends io.flutter.plugin.common.MethodChannel$MethodCallHandler
-keep class * extends io.flutter.plugin.common.EventChannel$StreamHandler
*