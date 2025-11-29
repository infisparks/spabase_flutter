# Keep OkHttp3 classes
-dontwarn okhttp3.**
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }

# Keep Okio classes (used by OkHttp)
-dontwarn okio.**
-keep class okio.** { *; }
-keep interface okio.** { *; }

# Keep uCrop classes
-dontwarn com.yalantis.ucrop**
-keep class com.yalantis.ucrop** { *; }
-keep interface com.yalantis.ucrop** { *; }