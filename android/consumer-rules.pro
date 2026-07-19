# Reglas heredadas automáticamente por cualquier app que consuma este plugin y minifique su
# build de release (R8/ProGuard). Sin esto, PreferencesManager.kt (`object :
# TypeToken<Map<*, *>>() {}`) revienta en runtime con "Missing type parameter" apenas arranca
# IsolateHolderService — R8 borra la firma genérica que Gson necesita para resolver ese tipo. Ver
# docs/known-issues.md para el crash real que motivó esto (confirmado en producción, diagnosticado
# con adb logcat).
-keepattributes Signature
-keepattributes *Annotation*

-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}

-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken

-keep class yukams.app.background_locator_2.** { *; }
