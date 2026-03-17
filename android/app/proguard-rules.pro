
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

# Models (Keep all data classes to prevent serialization issues)
-keep class com.diasporanearby.diasporanearby.models.** { *; }
-keep class com.diasporanearby.models.** { *; } 
# Note: Verified package name in android/app/build.gradle is com.diasporanearby.diasporanearby
# But dart package is diaspora_nearby. 
# Proguard obfuscates Java/Kotlin classes. 
# Flutter/Dart code is minified by the Dart compiler, not Proguard.
# Proguard only affects Android Native code.
# Ensure Android plugins interacting with Dart don't break.
# Re-adding standard Flutter keep rules just in case.

# Just Audio
-keep class com.ryanheise.** { *; }

# Prevent obfuscation of some essential classes
-keep class * extends io.flutter.plugin.common.MethodChannel$MethodCallHandler
-keep class * extends io.flutter.plugin.common.EventChannel$StreamHandler

# Play Core Missing Classes (R8 Fix)
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task

# Isar
-keep class isar.** { *; }
-keep class com.isar.** { *; }

# Coroutines
-keep class kotlinx.coroutines.** { *; }

# Google ML Kit
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_** { *; }
-dontwarn com.google.mlkit.**
