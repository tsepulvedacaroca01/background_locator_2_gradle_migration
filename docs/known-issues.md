# Gotchas conocidos de este fork

Los tres primeros ya están documentados en `README.md` (público, en inglés — no duplicar el texto
acá, solo indexarlos). El resto son hallazgos hechos auditando este repo que **todavía no están en
el README**.

## Ya documentados en README.md

1. **AGP 9 / Gradle 9** — `jcenter()` legacy, orden del bloque `plugins {}`, tipado explícito de
   `hashMapOf<Any, Any>()` (§ "AGP 9 / Gradle 9 compatibility").
2. **Plugins de la app no registrados en el `FlutterEngine` de background** — resuelto por
   reflexión en `IsolateHolderExtension.registerAppPlugins()` (§ "App plugins not registered...").
   Ver `docs/android.md`.
3. **`BackgroundLocator.initialize()` obligatorio antes de `registerLocationUpdate()`** — sin esto
   el isolate nunca arranca (§ "BackgroundLocator.initialize() is required...").

## Gson `TypeToken` roto por R8 en apps consumidoras que minifican (Android)

`PreferencesManager.kt:207`:

```kotlin
val type = object : TypeToken<Map<*, *>>() {}.type
return Gson().fromJson(initialDataStr, type)
```

Esto lee `initDataCallback` (el `Map` que el usuario pasa a `registerLocationUpdate()`, ejecutado
por `InitPluggable.onServiceStart`). El patrón `TypeToken` anónimo necesita que R8/ProGuard
conserve la firma genérica del subtipo anónimo — sin eso, Gson no puede resolver el `Map<*, *>` en
runtime y tira:

```
java.lang.RuntimeException: Missing type parameter.
	at ... Gson$Types...
	at yukams.app.background_locator_2.PreferencesManager$Companion.getDataCallback(...)
	at ... IsolateHolderService.onStartCommand(...)
```

**Confirmado en producción**: una app consumidora de este fork tenía este crash exacto en
`app-release.apk` — el foreground service moría en cuanto arrancaba, apenas después de que la app
empezaba a trackear ubicación, y nunca en modo debug (R8 no corre en debug). Diagnosticado con
`adb logcat` + reproducción en dispositivo real.

Este módulo **no** ships un `consumer-rules.pro` — cualquier app que consuma este plugin con
`minifyEnabled true` (o el equivalente por default de plantillas Flutter recientes) tiene que
agregar las reglas de Gson a mano en su propio `android/app/proguard-rules.pro`:

```proguard
-keepattributes Signature
-keepattributes *Annotation*
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken
-keep class yukams.app.background_locator_2.** { *; }
```

**Pendiente real (no hecho todavía)**: agregar un `android/consumer-rules.pro` a este módulo con
estas reglas y referenciarlo desde `android/build.gradle` (`consumerProguardFiles`) — así
cualquier consumidor las hereda automáticamente en vez de tener que redescubrir este crash. Si se
hace, el workaround manual que cualquier consumidor haya agregado en su propio
`android/app/proguard-rules.pro` se puede simplificar (dejar solo el keep del paquete, o quitarlo
del todo).

## `catch` silenciosos sin loguear (Android)

Dos lugares en `IsolateHolderService.kt` atrapan `Exception` y no hacen nada con ella — exactamente
el patrón que causó que el bug de "plugins no registrados" (arriba) fuera invisible durante mucho
tiempo:

- `onMethodCall` (~línea 278): `catch (e: Exception) { }` — si `METHOD_SERVICE_INITIALIZED` u otro
  método falla acá, no queda ningún rastro en logcat.
- `onLocationUpdated` (~línea 325): `catch (e: Exception) { }` — si `PreferencesManager
  .getCallbackHandle` devuelve `null` (cast `as Long` fallando) o `sendLocationEvent` falla,
  ninguna ubicación llega al callback del usuario y no hay ninguna señal de por qué.

Si alguna vez hay que debuggear "no me llega nada al callback pero el servicio arranca bien",
estos dos `catch` son sospechosos directos — agregar `Log.e(..., e)` ahí (como ya se hizo en
`registerAppPlugins`, ver `docs/android.md`) antes de asumir que el problema está en otro lado.

## Metadata del `pubspec.yaml` apunta a otro fork

`homepage`/`repository` apuntan a `sultan18kh/background_locator_2_gradle_migration` e
`issue_tracker` a `Yukams/background_locator_fixed` — ninguno es
`tsepulvedacaroca01/background_locator_2_gradle_migration` (el remoto real de este repo). No
afecta el build (es solo metadata de `pub.dev`/`pub get`), pero puede confundir si alguien busca
"dónde está el código real" a partir del `pubspec.yaml` publicado.
