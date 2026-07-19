# API pública Dart

Todo vive en `lib/`. Es la única superficie que un consumidor toca directamente — nunca importa
nada de `android/` ni `ios/`.

## `BackgroundLocator` (`lib/background_locator.dart`)

| Método | Uso |
|---|---|
| `initialize()` | **Obligatorio antes de `registerLocationUpdate()`.** Persiste el handle de `callbackDispatcher` en el lado nativo — sin esto, `IsolateHolderService` no encuentra qué ejecutar y aborta en silencio (ver `docs/android.md`). |
| `registerLocationUpdate(callback, {initCallback, initDataCallback, disposeCallback, autoStop, androidSettings, iosSettings})` | Arranca el tracking. `callback` es obligatorio; el resto opcional. |
| `unRegisterLocationUpdate()` | Para el tracking. |
| `isRegisterLocationUpdate()` / `isServiceRunning()` | Mismo valor en la práctica — ambos delegan a `IsolateHolderService.isServiceRunning` del lado nativo. |
| `updateNotificationText({title, msg, bigMsg})` | Solo Android — actualiza la notificación del foreground service sin reiniciar el tracking. En iOS el nativo devuelve `nil` sin hacer nada (`MethodCallHelper.m`). |

Los cuatro callbacks (`callback`, `initCallback`, `disposeCallback`,
`notificationTapCallback` dentro de `AndroidNotificationSettings`) tienen que ser **top-level
functions o static methods**, marcados `@pragma('vm:entry-point')` — se resuelven del lado nativo
por `CallbackHandle`/`PluginUtilities.getCallbackHandle`, que no funciona con closures ni métodos
de instancia. Ver `example/lib/location_callback_handler.dart` para el patrón correcto.

## `AutoStopHandler` (`lib/auto_stop_handler.dart`)

Si `registerLocationUpdate(..., autoStop: true)`, se registra un `WidgetsBindingObserver` que
llama `unRegisterLocationUpdate()` cuando la app pasa a `inactive`/`paused`/`detached`. **No** usar
esto junto con tracking real en background — es para el caso "solo mientras la app está en
foreground", lo opuesto al propósito principal del plugin.

## Settings (`lib/settings/`)

```
LocatorSettings (accuracy, distanceFilter)
├── AndroidSettings   (+ interval, wakeLockTime, client, androidNotificationSettings)
└── IOSSettings       (+ showsBackgroundLocationIndicator, stopWithTerminate)
```

`LocationAccuracy` es un enum-como-clase con 5 niveles (`POWERSAVE`→`NAVIGATION`, valores 0-4) que
se mapean 1:1 a las constantes de prioridad nativas en cada plataforma (`LocationRequest.PRIORITY_*`
en Android vía `IsolateHolderExtension.getAccuracy()`, `CLLocationAccuracy` en iOS vía
`Util.getAccuracy:`).

`SettingsUtil.getArgumentsMap()` (`lib/utils/settings_util.dart`) arma el `Map` final que cruza el
canal — común primero (`_getCommonArgumentsMap`, los callback handles), después específico de
plataforma (`Platform.isAndroid`/`Platform.isIOS`) con `androidSettings.toMap()`/
`iosSettings.toMap()`.

## `LocationDto` (`lib/location_dto.dart`)

Forma final de cada actualización de ubicación que llega al `callback` del usuario. `isMocked`
solo se resuelve en Android (`Platform.isAndroid`, `location.isFromMockProvider` del lado nativo);
en iOS siempre `false`. `provider` puede venir vacío (`?? ''`) — un `Location` de Android sin
provider asignado es válido.

## Sincronización de claves — el punto más frágil de tocar

Las claves de `Keys` (nombres de método del canal, nombres de argumentos, nombres de settings)
están **duplicadas a mano** en tres archivos que no se validan entre sí en compile-time:

- `lib/keys.dart` (Dart, fuente de lo que el canal Dart→nativo envía/espera)
- `android/.../Keys.kt` (Kotlin)
- `ios/Classes/Globals.h` + `Globals.m` (Obj-C)

Si agregás un argumento o setting nuevo, tiene que existir en **las tres** con el mismo string
literal — un typo en cualquiera hace que `Map[key]` devuelva `null` del otro lado sin ningún error
visible (ni excepción, ni log), porque `MethodChannel` serializa a `Map<dynamic, dynamic>` y todo
lookup con clave equivocada es simplemente `null`, no una falla. `Keys.kt` tiene además dos claves
que **no** existen en `lib/keys.dart` (`SETTINGS_INIT_PLUGGABLE`, `SETTINGS_DISPOSABLE_PLUGGABLE`)
— son intencionalmente internas del lado Android (`BackgroundLocatorPlugin.startIsolateService`
las agrega al `Intent` según si hay o no `initCallback`/`disposeCallback` guardado), nunca viajan
desde Dart.
