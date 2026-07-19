# iOS

Todo el código nativo vive en `ios/Classes/`. Este fork **no ha tocado el lado iOS** — todos los
commits de este fork son sobre Android (compatibilidad AGP/Gradle, registro de plugins,
`Missing type parameter`). Lo que sigue es un mapa de cómo funciona hoy, para saber dónde tocar si
hace falta.

## `BackgroundLocatorPlugin.m` — headless runner en vez de foreground service

A diferencia de Android (un `Service` real), iOS no tiene un concepto directo de "servicio en
background" para esto — el plugin usa un segundo `FlutterEngine` **headless**
(`allowHeadlessExecution:YES`, `_headlessRunner`), creado una sola vez en `init:` (cuando el
plugin principal se registra), no bajo demanda como en Android.

```
registerLocator: (registerLocationUpdate del canal Dart)
  → CLLocationManager.requestAlwaysAuthorization + startUpdatingLocation +
    startMonitoringSignificantLocationChanges
  → startLocatorService: (equivalente a startLocatorService de Android)
      → PreferencesManager setCallbackDispatcherHandle:
      → FlutterCallbackCache lookupCallbackInformation: (NSAssert si no está — en iOS un
        `initialize()` faltante literalmente crashea la app en vez de solo loguear un error,
        distinto del `return` silencioso de Android)
      → _headlessRunner runWithEntrypoint:libraryURI: (ejecuta callbackDispatcher())
      → registerPlugins(_headlessRunner) — dispatch_once, solo la primera vez
```

`registerPlugins` es un `FlutterPluginRegistrantCallback` que **el consumidor tiene que setear a
mano** desde su propio `AppDelegate.m`/`AppDelegate.swift`:

```objc
[BackgroundLocatorPlugin setPluginRegistrantCallback:registerPlugins];
```

donde `registerPlugins` suele ser un wrapper sobre `GeneratedPluginRegistrant registerWithRegistry:`
del propio proyecto. Es el equivalente exacto al `registerAppPlugins()` por reflexión que este
fork agregó en Android (`IsolateHolderExtension.kt`) — pero en iOS **siempre existió** como
requisito documentado (`NSAssert(registerPlugins != nil, @"failed to set registerPlugins")`), no
hubo que arreglarlo. Si un consumidor solo sigue el wiki de Android y no configura esto en iOS,
cualquier plugin de canal de plataforma usado dentro del callback va a fallar ahí también.

## Relanzamiento tras kill total

`didFinishLaunchingWithOptions:` chequea `UIApplicationLaunchOptionsLocationKey` — si iOS
relanzó la app específicamente porque llegó un evento de ubicación (app killeada, no solo en
background), reinicia el locator service leyendo el `callbackDispatcher` handle guardado. Esto es
lo que le da a iOS un comportamiento parecido al `BootBroadcastReceiver` de Android, pero
disparado por evento de ubicación en vez de por boot del dispositivo.

## Region monitoring como fallback

Cuando la app entra en background real (`applicationDidEnterBackground:`), además de
`startMonitoringSignificantLocationChanges` arma una `CLCircularRegion` alrededor de la última
posición conocida (`observeRegionForLocation:`, radio = `distanceFilter`) — el sistema puede
despertar la app por salir de esa región incluso con el proceso completamente descargado, lo cual
dispara el flujo de relanzamiento de arriba.

## `PreferencesManager` (iOS) — `NSUserDefaults`

Equivalente directo al `PreferencesManager.kt` de Android pero sobre `NSUserDefaults` en vez de
`SharedPreferences` — mismo propósito (persistir callback handles + settings para sobrevivir a un
relanzamiento sin pasar por Dart). Claves en `Globals.h`/`Globals.m`, deben mantenerse en paralelo
con `Keys.kt` (Android) y `keys.dart` (Dart) — ver `docs/dart-api.md` § Sincronización de claves.

## `InitPluggable`/`DisposePluggable` (iOS)

Misma semántica que en Android (`docs/android.md` § Pluggables) — `onServiceStart:`/
`onServiceDispose` disparan `BCM_INIT`/`BCM_DISPOSE` por el canal background. La diferencia es que
acá el `initDataDictionary` viaja como `NSDictionary` nativo (sin paso por Gson/JSON) — el
problema de `docs/known-issues.md` (Gson `TypeToken` roto por R8) es **específico de Android**, no
aplica acá.
