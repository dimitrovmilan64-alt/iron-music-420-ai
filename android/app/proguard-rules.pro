# sherpa-onnx JNI (libsherpa-onnx-jni.so) uses GetFieldID / GetMethodID on
# the original Kotlin field names and type descriptors. Flutter 3.47 enables
# R8 minify on release builds, and the official AAR ships an empty proguard.txt,
# so without these keep rules KeywordSpotterConfig.maxActivePaths (and other
# fields) are renamed or stripped. That produces:
#   RuntimeException: Failed to get field ID for maxActivePaths
-keep class com.k2fsa.sherpa.onnx.** { *; }
-keepclassmembers class com.k2fsa.sherpa.onnx.** { *; }
-keepnames class com.k2fsa.sherpa.onnx.** { *; }
-dontwarn com.k2fsa.sherpa.onnx.**
