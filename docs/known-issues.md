# Gotchas conocidos de este fork

Los primeros ya están documentados en `README.md` (público, en inglés). El resto son hallazgos
hechos auditando este repo que **todavía no están en el README** — por ahora solo importan a quien
mantiene este fork, no a un consumidor.

## Ya documentados en README.md

No duplicar el texto acá — solo indexarlos y, si hace falta, agregar detalle de diagnóstico interno
que no le sirve a un consumidor pero sí a quien mantenga este repo (línea de código exacta, cómo se
encontró, cómo se verificó).

1. **AGP 9 / Gradle 9** — `jcenter()` legacy, orden del bloque `plugins {}`, tipado explícito de
   `hashMapOf<Any, Any>()` (§ "AGP 9 / Gradle 9 compatibility").
2. **Plugins de la app no registrados en el `FlutterEngine` de background** — resuelto por
   reflexión en `IsolateHolderExtension.registerAppPlugins()` (§ "App plugins not registered...").
   Ver `docs/android.md`.
3. **`BackgroundLocator.initialize()` obligatorio antes de `registerLocationUpdate()`** — sin esto
   el isolate nunca arranca (§ "BackgroundLocator.initialize() is required...").
4. **`FOREGROUND_SERVICE_LOCATION` requerido en Android 14+** — sin este permiso en el manifest del
   consumidor, `IsolateHolderService.onCreate()` revienta con `SecurityException` en cualquier app
   con `targetSdk >= 34` (§ "`FOREGROUND_SERVICE_LOCATION` required on Android 14+"). Ver también
   `docs/android.md` § Permisos requeridos en el manifest del consumidor.
5. **Gson `TypeToken` roto por R8** — resuelto con `android/consumer-rules.pro`
   (`consumerProguardFiles`), heredado automáticamente por cualquier consumidor (§ "Gson/R8 crash
   fixed automatically..."). Detalle de diagnóstico abajo.
6. **`initCallback` nunca se ejecutaba** (`BCM_INIT`) — `TypeError` silencioso por un `Map` sin
   castear (§ "`initCallback` fix — was silently never firing"). Detalle de diagnóstico abajo.

### Detalle de diagnóstico — Gson `TypeToken` + R8 (ítem 5)

`PreferencesManager.kt:207` (`object : TypeToken<Map<*, *>>() {}.type` — lee `initDataCallback` en
`InitPluggable.onServiceStart`). **Confirmado en producción**: una app consumidora tenía este crash
exacto en `app-release.apk` — el foreground service moría apenas arrancaba, nunca en modo debug (R8
no corre en debug). Diagnosticado con `adb logcat` + reproducción en dispositivo real:

```
java.lang.RuntimeException: Missing type parameter.
	at ... Gson$Types...
	at yukams.app.background_locator_2.PreferencesManager$Companion.getDataCallback(...)
	at ... IsolateHolderService.onStartCommand(...)
```

Verificado el fix con un build real (`flutter build apk --release` de una app consumidora
apuntando a este módulo por `path:`) — R8 corre y el resultado sigue siendo un APK instalable. Si
una app consumidora ya tenía este workaround copiado a mano en su propio
`android/app/proguard-rules.pro` (necesario con versiones de este fork anteriores a este fix),
ahora es redundante.

### Detalle de diagnóstico — `initCallback` / `BCM_INIT` (ítem 6)

`lib/callback_dispatcher.dart`, rama `BCM_INIT`. Error exacto en runtime (para buscarlo en logs si
reaparece en otro punto del código):

```
type '_Map<Object?, Object?>' is not a subtype of type 'Map<String, dynamic>' of 'data'
```

Sin ningún log — el `TypeError` ocurre dentro del handler de `setMethodCallHandler`, en un `Future`
que nadie espera ni captura, así que el callback del usuario simplemente nunca corría, en silencio.
`example/lib/location_callback_handler.dart` no lo mostraba porque declara su `initCallback` con el
tipo más laxo `Map<dynamic, dynamic>` en vez del tipo público documentado — tapaba el bug por
accidente, no lo evitaba a propósito.

**Encontrado escribiendo `test/callback_dispatcher_test.dart`** (ver `docs/testing.md`) — el mismo
patrón de "un test nuevo revela un bug real" que ya pasó con el fix de plugins no registrados.
Resuelto con `Map<String, dynamic>.from(args[Keys.ARG_INIT_DATA_CALLBACK] as Map? ?? {})` antes de
invocar — sigue siendo válido para un consumidor que declaró su `initCallback` con el tipo laxo
(`Map<String, dynamic>` es asignable a `Map<dynamic, dynamic>`), así que no rompe a `example/`.

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
- **`IsolateHolderService.sendLocationEvent()` reusa el `MethodChannel` cacheado** en vez de crear
  uno nuevo en cada actualización de ubicación — este método corre en el hot path del servicio
  (potencialmente cada pocos segundos, durante horas). El campo `backgroundChannel` ya existía
  (seteado una sola vez en `startLocatorService()`), pero `sendLocationEvent()` no lo reusaba.
- **`onLocationUpdated()` ya no llama `FlutterInjector...ensureInitializationComplete()`** en cada
  ubicación — `FlutterEngine(context)` (creado una sola vez en `startLocatorService()`) ya garantiza
  la inicialización del loader antes de que pueda dispararse cualquier actualización (ver el
  javadoc de `FlutterEngine`: "The first FlutterEngine instance constructed per process will also
  load the Flutter native library and start a Dart VM"). La llamada repetida era de bajo costo
  (`ensureInitializationComplete` hace `if (initialized) return` como primera línea) pero
  igualmente redundante en un método que corre potencialmente cientos de veces por sesión.

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
5. **`FOREGROUND_SERVICE_LOCATION` faltante** — no específico de `example/`, ver ítem 4 de
   "Ya documentados en README.md" arriba. Es lo que confirmó, con un crash real en `adb logcat`,
   que cualquier app consumidora con `targetSdk >= 34` necesita este permiso.

Verificado end-to-end en un dispositivo real: `flutter build apk --release` en `example/`,
instalado, permisos de ubicación otorgados, botón "Start" tocado — el foreground service arranca,
el `FlutterEngine` secundario registra los plugins de la app y ejecuta el callback, y llegan
ubicaciones reales al callback del usuario. Sin `FATAL EXCEPTION` en logcat.

`flutter pub get --no-example` sigue funcionando por compatibilidad, pero ya no es necesario —
`flutter pub get`/`flutter test` resuelven todo el repo sin flags especiales.

## Investigado y descartado — warning "apply plugins that apply KGP" (Built-in Kotlin de AGP 9)

Flutter 3.44+ tira este warning cuando un consumidor en AGP 9+ usa un plugin que aplica el Kotlin
Gradle Plugin (KGP) él mismo — es el caso de `android/build.gradle` (`id
'org.jetbrains.kotlin.android'`), que hoy sigue siendo necesario. Se investigó migrar a "Built-in
Kotlin" (que AGP 9 puede proveer sin declarar el plugin) y **no se pudo hacer de forma segura
todavía** — quedan tres intentos reales, los tres fallaron, probados contra una app consumidora
real (`gms_flutter`, Flutter 3.44.4 / AGP 9.0.1):

1. **No aplicar el plugin, sin ninguna otra condición** (`plugins { id 'com.android.library' }` +
   bloque `kotlin { compilerOptions {...} }` a nivel de archivo, tal como indica la guía oficial de
   migración) → `Could not find method kotlin() for arguments [...]`. La extensión `kotlin {}` no
   existe sin aplicar el plugin — **Built-in Kotlin no está activo por default**, ni siquiera en
   AGP 9: la plantilla actual de Flutter trae `android.builtInKotlin=false` en `gradle.properties`
   del consumidor (confirmado en `gms_flutter/android/gradle.properties`).
2. **Aplicar el plugin condicionalmente** (`apply plugin: 'kotlin-android'` fuera del bloque
   `plugins {}`, ya que ese bloque no admite lógica condicional) solo cuando
   `android.builtInKotlin` es `false` → compila, pero con referencias cruzadas rotas dentro del
   propio módulo (`Unresolved reference 'startLocatorService'`, `'GoogleLocationProviderClient'`,
   etc.) — mezclar el `plugins {}` declarativo (que resuelve la versión de Kotlin vía
   `pluginManagement` del consumidor) con `apply plugin:` imperativo (mecanismo viejo, pensado para
   resolver la versión desde un `buildscript {}` con classpath que este módulo ya no tiene desde la
   migración a AGP 9) deja el compilador de Kotlin en un estado roto — no es solo una cuestión de
   orden, es una resolución de plugin distinta e incompatible entre sí.
3. **Prender `android.builtInKotlin=true` en el consumidor** (para validar que el módulo sin KGP sí
   compila con esa flag) → **rompe el build entero**, ni siquiera llega a evaluar este módulo:
   `IllegalStateException: The 'org.jetbrains.kotlin.android' plugin is no longer required for
   Kotlin support since AGP 9.0`. Con esa flag activa, AGP directamente **prohíbe** que cualquier
   módulo del build (no solo este) aplique el plugin de Kotlin clásico — y `mobile_scanner` (otro
   plugin de `gms_flutter`, fuera de nuestro control) todavía lo aplica. La flag es global al
   build, no por módulo, así que no hay forma de activarla "solo para nuestra librería".

**Conclusión**: migrar a Built-in Kotlin requiere que **todos** los plugins de un consumidor lo
hagan al mismo tiempo (uno solo que no migre bloquea la flag globalmente), y la migración condicional
que sí preservaría compatibilidad hacia atrás no funciona en este Gradle/AGP tal como está armado
hoy. `android/build.gradle` se dejó como estaba (aplicando `org.jetbrains.kotlin.android` en el
bloque `plugins {}`) — es la única configuración de las cuatro probadas que compila. Revisar de
nuevo cuando el ecosistema de plugins Flutter (`mobile_scanner` incluido) termine de migrar, o
cuando Flutter/AGP maduren el soporte condicional — mientras tanto, el warning es correcto: "Future
versions of Flutter will fail" es una advertencia a futuro, no una falla actual.

## Metadata del `pubspec.yaml` apunta a otro fork

`homepage`/`repository` apuntan a `sultan18kh/background_locator_2_gradle_migration` e
`issue_tracker` a `Yukams/background_locator_fixed` — ninguno es
`tsepulvedacaroca01/background_locator_2_gradle_migration` (el remoto real de este repo). No
afecta el build (es solo metadata de `pub.dev`/`pub get`), pero puede confundir si alguien busca
"dónde está el código real" a partir del `pubspec.yaml` publicado.
