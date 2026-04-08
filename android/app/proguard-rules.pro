# ══════════════════════════════════════════════════════════════════════════════
# KanMon GO — ProGuard Rules
# ══════════════════════════════════════════════════════════════════════════════

# ── Flutter core ──────────────────────────────────────────────────────────────
-keep class io.flutter.** { *; }
-keep class io.flutter.app.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-dontwarn io.flutter.**

# ── App classes ───────────────────────────────────────────────────────────────
-keep class com.kanmongo.app.** { *; }

# ── LlamaPlugin JNI Bridge — WAJIB agar R8 tidak obfuscate ──────────────────
# Tanpa ini: GetMethodID("onToken") / "onError" return null di release → crash
-keep class com.kanmongo.app.LlamaPlugin { *; }
-keep interface com.kanmongo.app.LlamaPlugin$TokenCallback { *; }
-keepclassmembers class com.kanmongo.app.LlamaPlugin$* {
    public *;
}
-keepclasseswithmembernames class com.kanmongo.app.LlamaPlugin {
    native <methods>;
}

# ── Kotlin ────────────────────────────────────────────────────────────────────
-keep class kotlin.** { *; }
-keep class kotlinx.** { *; }
-dontwarn kotlin.**
-dontwarn kotlinx.**

# ── AndroidX / Jetpack ────────────────────────────────────────────────────────
-keep class androidx.** { *; }
-dontwarn androidx.**
-keep class androidx.core.content.FileProvider { *; }
-keep class androidx.multidex.** { *; }

# ── SQLite / sqflite ──────────────────────────────────────────────────────────
-keep class com.tekartik.sqflite.** { *; }
-dontwarn com.tekartik.sqflite.**

# ── shared_preferences ────────────────────────────────────────────────────────
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# ── path_provider ─────────────────────────────────────────────────────────────
-keep class io.flutter.plugins.pathprovider.** { *; }

# ── flutter_svg ───────────────────────────────────────────────────────────────
-keep class com.flutter_svg.** { *; }

# ── Google Fonts ──────────────────────────────────────────────────────────────
-keep class com.google.fonts.** { *; }
-dontwarn com.google.fonts.**

# ── cached_network_image ──────────────────────────────────────────────────────
-keep class com.baseflow.cachednetworkimage.** { *; }
-dontwarn com.baseflow.cachednetworkimage.**

# ── file_picker ───────────────────────────────────────────────────────────────
-keep class com.mr.flutter.plugin.filepicker.** { *; }
-dontwarn com.mr.flutter.plugin.filepicker.**

# ── open_file ─────────────────────────────────────────────────────────────────
-keep class com.crazecoder.openfile.** { *; }
-dontwarn com.crazecoder.openfile.**

# ── audioplayers ──────────────────────────────────────────────────────────────
-keep class xyz.luan.audioplayers.** { *; }
-dontwarn xyz.luan.audioplayers.**

# ── video_player / ExoPlayer / Media3 ────────────────────────────────────────
-keep class com.google.android.exoplayer2.** { *; }
-dontwarn com.google.android.exoplayer2.**
-keep class androidx.media3.** { *; }
-dontwarn androidx.media3.**
-keep class io.flutter.plugins.videoplayer.** { *; }

# ── flutter_tts ───────────────────────────────────────────────────────────────
-keep class com.tundralabs.fluttertts.** { *; }
-dontwarn com.tundralabs.fluttertts.**

# ── connectivity_plus ─────────────────────────────────────────────────────────
-keep class dev.fluttercommunity.plus.connectivity.** { *; }
-dontwarn dev.fluttercommunity.plus.connectivity.**

# ── Syncfusion PDF Viewer ─────────────────────────────────────────────────────
-keep class com.syncfusion.** { *; }
-dontwarn com.syncfusion.**

# ── Google Play Core (Flutter deferred components) ───────────────────────────
-dontwarn com.google.android.play.core.**

# ── Annotations & Signatures ──────────────────────────────────────────────────
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses

# ── JSON / Serialization ──────────────────────────────────────────────────────
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# ── Suppress verbose logging in release ───────────────────────────────────────
-assumenosideeffects class android.util.Log {
    public static boolean isLoggable(java.lang.String, int);
    public static int v(...);
    public static int d(...);
    public static int i(...);
}

# ── permission_handler ────────────────────────────────────────────────────────
-keep class com.baseflow.permissionhandler.** { *; }
-dontwarn com.baseflow.permissionhandler.**

# ── Google ML Kit — Text Recognition ─────────────────────────────────────────
# Required: tanpa ini R8 akan strip kelas script language yang tidak dipakai
-keep class com.google.mlkit.** { *; }
-keep class com.google_mlkit_text_recognition.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google_mlkit_text_recognition.**

# Keep semua script-specific recognizer options (Japanese, Chinese, Korean, Devanagari)
-keep class com.google.mlkit.vision.text.** { *; }
-keep class com.google.mlkit.vision.text.chinese.** { *; }
-keep class com.google.mlkit.vision.text.devanagari.** { *; }
-keep class com.google.mlkit.vision.text.japanese.** { *; }
-keep class com.google.mlkit.vision.text.korean.** { *; }
-dontwarn com.google.mlkit.vision.text.**
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# Google ML Kit internal dependencies
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# ── image_picker ──────────────────────────────────────────────────────────────
-keep class io.flutter.plugins.imagepicker.** { *; }
-dontwarn io.flutter.plugins.imagepicker.**

# ── http / Dart IO ────────────────────────────────────────────────────────────
-dontwarn java.net.**
-dontwarn javax.net.**

# ── speech_to_text ────────────────────────────────────────────────────────────
-keep class com.dexterous.flutterspeech.** { *; }
-dontwarn com.dexterous.flutterspeech.**
# Android SpeechRecognizer (used by speech_to_text)
-keep class android.speech.** { *; }
-dontwarn android.speech.**

# ── OkHttp / http package ─────────────────────────────────────────────────────
-dontwarn okhttp3.**
-dontwarn okio.**

# ── camera ────────────────────────────────────────────────────────────────────
-keep class io.flutter.plugins.camera.** { *; }
-dontwarn io.flutter.plugins.camera.**

# ── photo_manager ─────────────────────────────────────────────────────────────
-keep class com.fluttercandies.photo_manager.** { *; }
-dontwarn com.fluttercandies.photo_manager.**


# ── share_plus ────────────────────────────────────────────────────────────────
-keep class dev.fluttercommunity.plus.share.** { *; }
-dontwarn dev.fluttercommunity.plus.share.**





# ── html package (dart) ───────────────────────────────────────────────────────
-dontwarn org.w3c.dom.**

# ── process_run ───────────────────────────────────────────────────────────────
-dontwarn com.example.process_run.**
