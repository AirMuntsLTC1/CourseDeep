-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class com.coursedeep.coursedeep.MainActivity { *; }
-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
}
