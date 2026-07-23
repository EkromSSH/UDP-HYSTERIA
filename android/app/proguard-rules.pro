# EkromSSH VPN ProGuard Rules

# Keep Flutter engine
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep Play Core (required by Flutter deferred components)
-keep class com.google.android.play.core.** { *; }

# Keep our service classes
-keep class com.ekromssh.app.** { *; }

# Keep JSch (SSH library)
-keep class com.jcraft.jsch.** { *; }
-keep class com.jcraft.jzlib.** { *; }
-keep class org.ietf.jgss.** { *; }

# Keep OkHttp (WebSocket)
-keep class okhttp3.** { *; }
-keep class okio.** { *; }

# Keep Hysteria Go bindings
-keep class com.ekromssh.hysteria.** { *; }

# Keep Kotlin coroutines
-keep class kotlinx.coroutines.** { *; }

# Don't obfuscate
-dontobfuscate

# Optimize
-optimizations !code/simplification/arithmetic
-optimizationpasses 5
