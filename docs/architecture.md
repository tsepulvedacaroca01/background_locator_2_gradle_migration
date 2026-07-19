# Arquitectura

`background_locator_2` es un plugin Flutter que corre un `LocationManager`/`CLLocationManager`
**fuera** del ciclo de vida normal de la app — sigue reportando ubicación aunque la Activity/UIView
esté cerrada o la app killeada. Para lograrlo levanta un **segundo `FlutterEngine`** (Android) o un
**`FlutterEngine` headless** (iOS) que no dibuja nada, solo ejecuta un entrypoint Dart aislado
(`callbackDispatcher`) y se comunica con el motor principal por `SharedPreferences`/`NSUserDefaults`
más dos `MethodChannel`.

## Los dos canales

| Canal | Nombre | Dirección | Para qué |
|---|---|---|---|
| Principal | `app.yukams/locator_plugin` (`Keys.CHANNEL_ID`) | Dart app → nativo | `initialize()`, `registerLocationUpdate()`, `unRegisterLocationUpdate()`, `isServiceRunning()`, `updateNotificationText()` |
| Background | `app.yukams/locator_plugin_background` (`Keys.BACKGROUND_CHANNEL_ID`) | nativo ↔ isolate en background | nativo empuja `BCM_SEND_LOCATION`/`BCM_INIT`/`BCM_DISPOSE`/`BCM_NOTIFICATION_CLICK`; el isolate contesta `LocatorService.initialized` |

El canal background vive **dentro del `FlutterEngine` secundario** — `lib/callback_dispatcher.dart`
es el entrypoint que ese motor ejecuta (marcado `@pragma('vm:entry-point')` para que el tree
shaking/AOT no lo elimine), y ahí es donde se registra el `setMethodCallHandler` que resuelve los
callbacks reales del usuario vía `PluginUtilities.getCallbackFromHandle`.

## Flujo completo (arranque)

```
App Dart
  → BackgroundLocator.initialize()
      → canal principal: LocatorPlugin.initializeService { callbackDispatcher: <handle> }
      → nativo persiste ese handle (SharedPreferences en Android, NSUserDefaults en iOS)
        — es lo único que necesita sobrevivir a un reinicio del proceso

  → BackgroundLocator.registerLocationUpdate(callback, ...)
      → SettingsUtil.getArgumentsMap() arma un Map con los CallbackHandle (callback/initCallback/
        disposeCallback/notificationTapCallback) + AndroidSettings/IOSSettings serializados
      → canal principal: LocatorPlugin.registerLocationUpdate { ... }
      → nativo persiste settings + handles, arranca el foreground service (Android) o
        CLLocationManager + FlutterEngine headless (iOS)
      → nativo crea el FlutterEngine secundario y ejecuta callbackDispatcher (ver docs/android.md
        / docs/ios.md — el mecanismo difiere bastante entre plataformas)
      → callbackDispatcher() corre en ese motor, registra su propio setMethodCallHandler en el
        canal background, y avisa LocatorService.initialized

Actualización de ubicación (loop)
  → LocationManager/CLLocationManager entrega una posición al código nativo
  → nativo arma un Map con LocationDto (ver docs/dart-api.md) y lo empuja por el canal
    background: BCM_SEND_LOCATION { callback: <handle>, location: {...} }
  → callbackDispatcher() resuelve `callback` con PluginUtilities.getCallbackFromHandle y lo invoca
    con un LocationDto ya parseado — este es el callback que el usuario pasó a
    registerLocationUpdate()
```

## Pluggables (`InitPluggable` / `DisposePluggable`)

Dos hooks opcionales, uno por evento del ciclo de vida del servicio nativo — no de cada
actualización de ubicación:

- **`InitPluggable`** — corre una vez, en `onServiceStart` (arranque del servicio/engine), antes de
  la primera ubicación. Manda `BCM_INIT` con el `initDataCallback` que el usuario pasó a
  `registerLocationUpdate()` (serializado con Gson en Android — ver docs/known-issues.md, con JSON
  nativo en iOS).
- **`DisposePluggable`** — corre en `onServiceDispose` (`unRegisterLocationUpdate()` o shutdown).
  Manda `BCM_DISPOSE`, sin datos.

Ambos son opcionales — solo se instancian si `intent.hasExtra(SETTINGS_INIT_PLUGGABLE)` /
`SETTINGS_DISPOSABLE_PLUGGABLE` (Android) o si el handle correspondiente no es nulo (iOS), lo cual
depende de que el usuario haya pasado `initCallback`/`disposeCallback` a
`registerLocationUpdate()`.

## Ver también

- `docs/android.md` — implementación nativa Android, foreground service, reinicio tras reboot/crash
- `docs/ios.md` — implementación nativa iOS, headless runner, region monitoring
- `docs/dart-api.md` — API pública Dart y la tabla de claves que debe mantenerse sincronizada entre
  las tres plataformas
- `docs/known-issues.md` — gotchas de este fork y bugs latentes conocidos
