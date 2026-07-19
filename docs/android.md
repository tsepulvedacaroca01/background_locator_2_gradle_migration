# Android

Todo el código nativo vive en `android/src/main/kotlin/yukams/app/background_locator_2/`.

## Permisos requeridos en el manifest del consumidor

Además de `ACCESS_FINE_LOCATION`/`ACCESS_COARSE_LOCATION`/`ACCESS_BACKGROUND_LOCATION`,
`FOREGROUND_SERVICE` y `WAKE_LOCK`: con `targetSdk >= 34` (Android 14) también hace falta
declarar `android.permission.FOREGROUND_SERVICE_LOCATION` — sin eso,
`IsolateHolderService.onCreate()` revienta con `SecurityException` apenas llama a
`startForeground()`, incluso con los permisos de ubicación en runtime ya otorgados. Confirmado con
un crash real (`example/`, ver `docs/known-issues.md`):

```
SecurityException: Starting FGS with type location ... requires permissions: all of the
permissions allOf=true [android.permission.FOREGROUND_SERVICE_LOCATION] ...
```

## `IsolateHolderService` — el foreground service

`IsolateHolderService.kt` es un `Service` normal (no `bindService`, `onBind` devuelve `null`) que
se arranca con `ContextCompat.startForegroundService()` desde `BackgroundLocatorPlugin.kt`. Su
`onStartCommand` despacha por `intent.action`:

| Action | Qué hace |
|---|---|
| `START` | si ya estaba corriendo, primero hace shutdown (`shutdownHolderService()`) y vuelve a arrancar (`startHolderService()`) — nunca corren dos instancias en paralelo |
| `SHUTDOWN` | libera el wake lock, quita el listener de ubicación, `stopForeground` + `stopSelf`, dispara `Pluggable.onServiceDispose` en cada pluggable registrado |
| `UPDATE_NOTIFICATION` | solo si `isServiceRunning`, reconstruye y vuelve a postear la notificación |

Devuelve `START_STICKY` — si Android mata el proceso por presión de memoria, el sistema intenta
recrear el servicio con un `intent == null`; ese caso está manejado explícitamente arriba de todo
en `onStartCommand`: si a esa altura ya no hay permiso de ubicación, se llama `stopSelf()` en vez
de reintentar indefinidamente.

`onCreate()` llama a `startLocatorService(this)` (la extensión de abajo) **antes** de
`startForeground()` — el motor Flutter secundario se crea ahí, no en `onStartCommand`.

## `IsolateHolderExtension.kt` — arranque del `FlutterEngine` secundario

`startLocatorService()` es una función de extensión (no un método de la clase, para mantener
`IsolateHolderService.kt` más chico) que:

1. Destruye cualquier `backgroundEngine` previo (`IsolateHolderService.backgroundEngine?.destroy()`)
   — evita quedar "pegado" si la app crasheó con el motor anterior a medio inicializar.
2. Crea `FlutterEngine(context)` — un motor sin ninguna vista asociada.
3. **Registra los plugins de la app consumidora** en ese motor (`registerAppPlugins`, ver más
   abajo) — sin esto, cualquier plugin con canal de plataforma usado dentro del callback del
   usuario (`shared_preferences`, `path_provider`, etc.) revienta con `MissingPluginException`.
4. Busca el `callbackHandle` de `callbackDispatcher` guardado por `BackgroundLocator.initialize()`
   en `SharedPreferences` (`Keys.CALLBACK_DISPATCHER_HANDLE_KEY`). Si no está (`callbackInfo ==
   null`), loguea `"Fatal: failed to find callback"` y **retorna sin ejecutar nada más** — el
   isolate Dart nunca arranca, ni una sola línea de `callbackDispatcher()` corre. Esto pasa si el
   consumidor llama `registerLocationUpdate()` sin haber llamado `initialize()` antes.
5. Ejecuta el callback Dart con `executeDartCallback(DartExecutor.DartCallback(...))`.

```
⚠️ registerAppPlugins() usa reflexión (`Class.forName("io.flutter.plugins.GeneratedPluginRegistrant")`)
porque esa clase se genera dentro del módulo `app` de cada proyecto consumidor — este módulo (una
librería Android normal) no puede importarla en tiempo de compilación. Atrapa `Throwable`, no
`Exception` — `Class.forName`/`invoke` pueden lanzar subclases de `Error` (`NoClassDefFoundError`,
etc.) que un `catch (e: Exception)` no atrapa, y que abortarían todo `startLocatorService` en
silencio si no se loguean. Confirmar que funcionó buscando en logcat:
`IsolateHolderExtension: App plugins registered on background engine OK`.
```

## `PreferencesManager.kt` — persistencia entre reinicios

Todo lo que el isolate en background necesita para volver a arrancar sin que el motor principal
de la app haya corrido (reboot del dispositivo, o el servicio matado y recreado por el sistema) se
guarda en `SharedPreferences`, dos archivos separados por constante:

- `Keys.SHARED_PREFERENCES_KEY` ("SHARED_PREFERENCES_KEY") — callback handles individuales
  (`CALLBACK_HANDLE_KEY`, `INIT_CALLBACK_HANDLE_KEY`, `DISPOSE_CALLBACK_HANDLE_KEY`,
  `NOTIFICATION_CALLBACK_HANDLE_KEY`) y el `callbackDispatcher` handle.
- `PREF_NAME` ("background_locator_2", constante privada de `PreferencesManager`) — el mapa de
  `AndroidSettings` completo (`saveSettings`/`getSettings`), para poder reconstruir el `Intent` que
  arranca el servicio sin pasar por Dart.

`BootBroadcastReceiver.kt` escucha `BOOT_COMPLETED` y llama
`BackgroundLocatorPlugin.registerAfterBoot()`, que lee `PreferencesManager.getSettings()` y
arranca el servicio directo — **nunca pasa por el canal Dart**, por eso todo tiene que estar en
`SharedPreferences` de antemano.

```
⚠️ La declaración del `<receiver>` para `BOOT_COMPLETED` NO está en el `AndroidManifest.xml` de
este módulo (`android/src/main/AndroidManifest.xml` está vacío — `<manifest></manifest>`). Si un
consumidor quiere que el tracking sobreviva a un reboot, tiene que declarar el receiver en SU
PROPIO manifest:

    <receiver android:name="yukams.app.background_locator_2.BootBroadcastReceiver"
        android:exported="true">
      <intent-filter>
        <action android:name="android.intent.action.BOOT_COMPLETED"/>
      </intent-filter>
    </receiver>

y pedir el permiso `RECEIVE_BOOT_COMPLETED`. Sin ese registro, el tracking no sobrevive a un
reboot del teléfono, solo a que la app quede en background.
```

## R8/ProGuard — ver docs/known-issues.md

`PreferencesManager.getDataCallback()` usa Gson con un `TypeToken<Map<*, *>>()` anónimo — un
patrón que R8 rompe si el consumidor minifica sin las reglas de Gson correctas. Es la causa raíz
de un crash real ya diagnosticado (`java.lang.RuntimeException: Missing type parameter` al
arrancar `IsolateHolderService`). Detalle completo y la regla ProGuard exacta en
`docs/known-issues.md`.

## `LocationClient` — Google vs Android puro

`AndroidSettings.client` (`LocationClient.google` por default) elige entre dos implementaciones de
`BLLocationProvider`:

- `GoogleLocationProviderClient` — `FusedLocationProviderClient` de
  `com.google.android.gms:play-services-location`. Requiere Google Play Services en el
  dispositivo.
- `AndroidLocationProviderClient` — `LocationManager` puro de Android (GPS + NETWORK provider),
  sin dependencia de Play Services. Compara timestamps entre ambos providers para devolver la
  posición más reciente como primer valor.

`getLocationClient()` en `IsolateHolderService` decide cuál instanciar leyendo
`PreferencesManager.getLocationClient()` (persistido, no en memoria) — por eso el valor tiene que
guardarse en `saveSettings()` incluso aunque el servicio ya esté corriendo con el otro cliente.

## AGP 9 / Gradle 9 — compatibilidad de build

Los tres fixes de compatibilidad con AGP/Gradle modernos (bloque `plugins {}` sin `buildscript`
legacy, orden del bloque `plugins {}`, tipado explícito de `hashMapOf<Any, Any>`) están descritos
con detalle en el `README.md` § "AGP 9 / Gradle 9 compatibility" — no repetidos acá para no
desincronizar las dos fuentes. Si tocás `android/build.gradle` o
`provider/LocationParserUtil.kt`, leé esa sección primero.
