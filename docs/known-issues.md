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

## `example/` no resuelve en un SDK Dart moderno — usar `--no-example`

`flutter pub get`/`flutter test` en la raíz de este repo intentan resolver también las
dependencias de `example/` (comportamiento estándar de Flutter para packages de tipo plugin, para
que `cd example && flutter run` funcione solo). Eso falla en cualquier SDK Dart actual (probado
con 3.12.2) por dos motivos apilados en `example/pubspec.yaml`:

1. `environment.sdk: ">=2.8.0 <3.0.0"` — el lower bound (2.8.0) es anterior a null safety
   (mínimo 2.12.0); Dart 3.x ya no tiene modo legacy, así que rechaza la resolución directo.
2. Aunque se suba ese lower bound a 2.12.0, `location_permissions: ^3.0.0+1` (dependencia del
   example) tampoco soporta null safety en ninguna versión `<4.0.0` — haría falta migrar el
   example completo a `permission_handler` (como ya usa `docs/android.md`/`docs/ios.md` del lado
   nativo) para que compile en un SDK moderno. No se hizo — está fuera del alcance de mantener la
   librería en sí, el `example/` es solo referencia de uso del API.

**Workaround, no fix** — correr todo con `--no-example`:

```sh
flutter pub get --no-example
flutter test
```

`flutter test` reusa la resolución ya hecha por ese `pub get` y no vuelve a intentar tocar
`example/` mientras `pubspec.lock`/`.dart_tool/package_config.json` del root sigan al día.

## Metadata del `pubspec.yaml` apunta a otro fork

`homepage`/`repository` apuntan a `sultan18kh/background_locator_2_gradle_migration` e
`issue_tracker` a `Yukams/background_locator_fixed` — ninguno es
`tsepulvedacaroca01/background_locator_2_gradle_migration` (el remoto real de este repo). No
afecta el build (es solo metadata de `pub.dev`/`pub get`), pero puede confundir si alguien busca
"dónde está el código real" a partir del `pubspec.yaml` publicado.
