# Flutter Play Core library - blanket keep all classes
-keep class com.google.android.play.core.** { *; }
-keep class io.flutter.embedding.engine.deferredcomponents.** { *; }

# Don't warn about missing Play Core classes (not actually used at runtime)
-dontwarn com.google.android.play.core.**
