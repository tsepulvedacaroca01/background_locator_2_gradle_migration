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

**Resuelto** (`android/consumer-rules.pro`, referenciado desde `android/build.gradle` vía
`consumerProguardFiles`): cualquier app que consuma este plugin hereda estas reglas
automáticamente, minifique o no, sin tener que redescubrir el crash. Verificado con un build real
(`flutter build apk --release` de una app consumidora apuntando a este módulo por `path:`) — R8
corre y el resultado sigue siendo un APK instalable.

```proguard
-keepattributes Signature
-keepattributes *Annotation*
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken
-keep class yukams.app.background_locator_2.** { *; }
```

Si una app consumidora ya tenía este mismo workaround copiado a mano en su propio
`android/app/proguard-rules.pro` (necesario con versiones de este fork anteriores a este fix),
ahora es redundante — se puede simplificar o quitar, `consumerProguardFiles` ya lo cubre.

## `catch` silenciosos sin loguear (Android) — resuelto

`IsolateHolderService.kt` tenía dos `catch (e: Exception) { }` vacíos — exactamente el patrón que
causó que el bug de "plugins no registrados" (arriba) fuera invisible durante mucho tiempo. Ambos
ahora loguean con `Log.e`, mismo criterio que `registerAppPlugins` (`docs/android.md`):

- `onMethodCall` — si `METHOD_SERVICE_INITIALIZED` u otro método falla, antes no quedaba ningún
  rastro en logcat. Ahora: `Log.e("IsolateHolderService", "onMethodCall failed for ${call.method}", e)`.
- `onLocationUpdated` — si `PreferencesManager.getCallbackHandle` devuelve `null` (cast `as Long`
  fallando) o `sendLocationEvent` falla, ninguna ubicación llegaba al callback del usuario y no
  había ninguna señal de por qué. Ahora: `Log.e("IsolateHolderService", "onLocationUpdated failed
  to dispatch $location", e)`.

Si en el futuro se agrega un `catch` nuevo en código nativo de este repo, seguir el mismo patrón
— nunca un `catch` mudo (ver `CLAUDE.md` § Convenciones).

## Optimizaciones aplicadas (rama `major-update`)

- **`PreferencesManager.saveSettings()` — 18 `.apply()` a 1**: guardaba cada clave del `Map` de
  settings con su propio `sharedPreferences.edit()....apply()` — hasta 11 escrituras a disco
  separadas por cada `registerLocationUpdate()`. Ahora arma un solo `editor` y llama `.apply()`
  una vez al final. Mismo resultado, menos I/O — `SharedPreferences.Editor` ya soporta encadenar
  todos los `put*` antes de aplicar.
- **Dependencia `com.google.android.material:material:1.0.0` eliminada**
  (`android/build.gradle`) — sin ningún uso real en `android/src/` (verificado con `grep`). Es una
  dependencia de UI que un plugin sin UI propia (todo el trabajo pasa por `MethodChannel` y un
  foreground service) no debería arrastrar al build de cada consumidor.
- **`gson` 2.8.6 → 2.14.0, `play-services-location` 21.0.1 → 21.4.0** (`android/build.gradle`).
  Verificado con un build real (`flutter build apk --release` + instalación en dispositivo +
  `adb logcat`) de `example/` — el flujo completo (foreground service, `FlutterEngine` secundario,
  `InitPluggable` con Gson bajo R8, callback de ubicación) sigue funcionando igual con las
  versiones nuevas.

## `example/` — modernizado (antes no resolvía en un SDK Dart/AGP moderno)

Antes, `flutter pub get`/`flutter test` en la raíz fallaban al intentar resolver también
`example/` (comportamiento estándar de Flutter para packages de tipo plugin). Se corrigió de raíz,
no con un workaround — `example/` ahora compila, instala y corre en un dispositivo real:

1. **`example/pubspec.yaml`** — `environment.sdk` bajo `2.12.0` (pre-null-safety, Dart 3.x ya no
   tiene modo legacy) y `location_permissions` (sin soporte null-safety en ninguna versión) fueron
   la causa. Se subió el `sdk` a `">=2.17.0 <4.0.0"` y se migró a `permission_handler` (misma
   librería que ya recomiendan `docs/android.md`/`docs/ios.md`).
2. **`example/lib/*.dart`** — el código entero predataba null safety (`bool isRunning;` sin `?`,
   `SendPort` no-nullable asignado desde un `lookupPortByName()` que devuelve `SendPort?`, `pow()`
   devolviendo `num` asignado a `double`). Migrado campo por campo, sin cambiar la lógica.
3. **`example/android/`** — Gradle 7.6/AGP 4.1.3/Kotlin 1.7.20 con `buildscript{jcenter()}` legacy,
   incompatible con cualquier JDK moderno (`Unsupported class file major version`). Modernizado
   replicando el mismo patrón de `settings.gradle`/`build.gradle`/`app/build.gradle` ya probado en
   una app consumidora real (Gradle 9.1.0, AGP 9.0.1, Kotlin 2.3.20, `namespace`, `compileSdk 36`,
   `targetSdk 34`). De paso se borró `Application.kt` — una clase 100% comentada con imports rotos
   de la API v1 de Flutter (`PluginRegistrantCallback`, `FlutterMain`), sin ninguna referencia real
   en el manifest (que usa `${applicationName}`, el default de Flutter).
4. **`android:exported`** — `targetSdk 34` exige un valor explícito en cualquier componente con
   `<intent-filter>`; se agregó `android:exported="true"` a `MainActivity` y `android:exported=
   "false"` al `BootBroadcastReceiver` (no debe poder dispararlo otra app).
5. **`FOREGROUND_SERVICE_LOCATION` faltante** — con `targetSdk 34`, `IsolateHolderService.onCreate()`
   revienta con `SecurityException` al llamar `startForeground()` si el manifest no declara este
   permiso (además de `ACCESS_FINE_LOCATION`/`ACCESS_COARSE_LOCATION`, que ya estaban). No es
   específico de `example/` — **cualquier app consumidora con `targetSdk >= 34` necesita este
   permiso en su manifest** para que el foreground service arranque. Confirmado con el crash real
   en `adb logcat`:
   ```
   SecurityException: Starting FGS with type location ... requires permissions: all of the
   permissions allOf=true [android.permission.FOREGROUND_SERVICE_LOCATION] ...
   ```

Verificado end-to-end en un dispositivo real: `flutter build apk --release` en `example/`,
instalado, permisos de ubicación otorgados, botón "Start" tocado — el foreground service arranca,
el `FlutterEngine` secundario registra los plugins de la app y ejecuta el callback, y llegan
ubicaciones reales al callback del usuario. Sin `FATAL EXCEPTION` en logcat.

`flutter pub get --no-example` sigue funcionando por compatibilidad, pero ya no es necesario —
`flutter pub get`/`flutter test` resuelven todo el repo sin flags especiales.

## Metadata del `pubspec.yaml` apunta a otro fork

`homepage`/`repository` apuntan a `sultan18kh/background_locator_2_gradle_migration` e
`issue_tracker` a `Yukams/background_locator_fixed` — ninguno es
`tsepulvedacaroca01/background_locator_2_gradle_migration` (el remoto real de este repo). No
afecta el build (es solo metadata de `pub.dev`/`pub get`), pero puede confundir si alguien busca
"dónde está el código real" a partir del `pubspec.yaml` publicado.
