# Flutter core — do not strip, breaks reflection
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Dart obfuscation compatibility
-keep class io.flutter.embedding.engine.dart.** { *; }

# Keep app entrypoint
-keep class com.coursedeep.coursedeep.MainActivity { *; }

# Remove verbose logging in release
-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
    public static *** i(...);
}
