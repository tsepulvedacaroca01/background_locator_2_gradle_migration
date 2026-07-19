# Testing

Este repo no tiene BLoCs ni widgets propios más allá de `AutoStopHandler` (un
`WidgetsBindingObserver` sin lógica propia que testear) — la pirámide de tests de una app no
aplica acá. Lo que sí hay es una API pública Dart delgada (`lib/`) que arma `Map`s para cruzar un
`MethodChannel`, y esa es la superficie que se testea.

---

## Qué se testea acá — dos niveles, no más

1. **Unit** — funciones/mapeos puros, sin `MethodChannel`, sin bindings. `LocationDto.fromJson`/
   `toJson`, `LocationAccuracy`, `AndroidSettings.toMap()`/`IOSSettings.toMap()`,
   `SettingsUtil.getArgumentsMap()`.
2. **API pública contra el canal mockeado** — `BackgroundLocator` (`lib/background_locator.dart`)
   invocado de verdad, verificando el `method` y los `arguments` exactos que le llegarían al lado
   nativo, sin ese lado nativo real (se mockea el `MethodChannel` con
   `TestDefaultBinaryMessengerBinding`).

**No hay tests nativos** (Kotlin/Obj-C) en este repo — no hay harness de test configurado
(Robolectric/JUnit del lado Android, XCTest del lado iOS). El comportamiento nativo (arranque del
`FlutterEngine` secundario, `IsolateHolderService`, persistencia en `SharedPreferences`) se
verifica manualmente contra un dispositivo real desde una app consumidora — ver `docs/android.md`
§ gotchas y `docs/known-issues.md` para los casos que ya causaron un crash real en producción.
**No hay integration_test tampoco** — requeriría levantar el foreground service Android de verdad,
fuera de alcance de este repo.

---

## Estructura de `test/`

Espeja `lib/` — mismo path relativo, sufijo `_test.dart`:

```
test/
├── background_locator_test.dart        # lib/background_locator.dart
├── location_dto_test.dart              # lib/location_dto.dart
├── settings/
│   ├── android_settings_test.dart      # lib/settings/android_settings.dart
│   ├── ios_settings_test.dart          # lib/settings/ios_settings.dart
│   └── locator_settings_test.dart      # lib/settings/locator_settings.dart
└── utils/
    └── settings_util_test.dart         # lib/utils/settings_util.dart
```

---

## 1. Unit tests — funciones puras

Sin mocks, `expect(fn(input), output)` directo:

```dart
// test/settings/locator_settings_test.dart
import 'package:background_locator_2/settings/locator_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LocationAccuracy', () {
    test('cubre los 5 niveles con sus valores nativos esperados', () {
      const cases = {
        LocationAccuracy.POWERSAVE: 0,
        LocationAccuracy.LOW: 1,
        LocationAccuracy.BALANCED: 2,
        LocationAccuracy.HIGH: 3,
        LocationAccuracy.NAVIGATION: 4,
      };

      for (final entry in cases.entries) {
        expect(entry.key.value, entry.value, reason: '${entry.key}');
      }
    });
  });
}
```

Cada `toMap()` de settings se testea contra **las claves nativas exactas** (`Keys.SETTINGS_*`), no
solo "algún valor" — es el mismo tipo de bug que ya costó un diagnóstico real (ver
`docs/dart-api.md` § Sincronización de claves): un typo en una clave no rompe la compilación, deja
el valor como `null` del lado nativo en silencio.

### Limitación real: `dart:io Platform` no es mockeable acá

`LocationDto.fromJson` (`isMocked`) y `SettingsUtil.getArgumentsMap` (settings de plataforma) leen
`Platform.isAndroid`/`Platform.isIOS` de `dart:io` directo, sin ningún wrapper inyectable. En
`flutter test` esas dos condiciones son **siempre `false`** — el proceso corre en el host de
desarrollo (Linux/macOS/Windows), no en un dispositivo. Consecuencias reales, ya reflejadas en los
tests:

- `LocationDto.fromJson(...).isMocked` da `false` sin importar el valor de `is_mocked` en el JSON
  de entrada.
- `SettingsUtil.getArgumentsMap(...)` nunca incluye `ARG_SETTINGS` — ni la rama Android ni la iOS
  corren.

No lo simules ni lo evites con trucos — **testeá el comportamiento real de esta suite en este
entorno** y dejá un comentario explicando por qué (ver `test/location_dto_test.dart` y
`test/utils/settings_util_test.dart`). Si en algún momento se justifica testear la rama
Android/iOS de `SettingsUtil` de verdad, la única forma es extraer un wrapper inyectable sobre
`Platform` — no se hizo todavía porque no hay otro consumidor que lo necesite (mismo criterio de
"no premature abstraction").

---

## 2. Tests de la API pública contra el `MethodChannel` mockeado

`BackgroundLocator` es un `MethodChannel` real (`Keys.CHANNEL_ID`) — se mockea con
`TestDefaultBinaryMessengerBinding`, capturando el último `MethodCall` recibido para assertear
`method` y `arguments` exactos:

```dart
// test/background_locator_test.dart
TestWidgetsFlutterBinding.ensureInitialized();

const channel = MethodChannel(Keys.CHANNEL_ID);
final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

late MethodCall lastCall;
dynamic mockResult;

setUp(() {
  mockResult = true;
  messenger.setMockMethodCallHandler(channel, (call) async {
    lastCall = call;
    return mockResult;
  });
});

tearDown(() => messenger.setMockMethodCallHandler(channel, null));

test('initialize() manda el método y el handle de callbackDispatcher', () async {
  await BackgroundLocator.initialize();

  expect(lastCall.method, Keys.METHOD_PLUGIN_INITIALIZE_SERVICE);
  expect(lastCall.arguments[Keys.ARG_CALLBACK_DISPATCHER], isA<int>());
});
```

**Por qué `TestWidgetsFlutterBinding.ensureInitialized()` es obligatorio acá**: sin un binding
inicializado, `TestDefaultBinaryMessengerBinding.instance` no existe todavía — cualquier test que
toque un `MethodChannel` real (mockeado o no) necesita esto al principio de `main()`.

**Por qué se verifican los `arguments` exactos y no solo que el método se haya llamado**: los
callbacks (`callback`, `initCallback`, `disposeCallback`) se resuelven a un `int` (`CallbackHandle
.toRawHandle()`) — un cambio que rompa esa resolución (ej. pasar una closure en vez de una función
top-level, ver `docs/dart-api.md`) no explota acá con una excepción visible, da un handle inválido
que el lado nativo no puede resolver. Verificar `isA<int>()` en el valor exacto de la clave
detecta ese tipo de regresión en el nivel Dart, sin necesitar un dispositivo real.

Callbacks pasados a estos tests (ej. `_locationCallback` en `background_locator_test.dart`) deben
ser top-level y `@pragma('vm:entry-point')`, igual que en código de producción — no por necesidad
técnica del test en sí, sino porque es la única forma válida de pasarle algo a
`PluginUtilities.getCallbackHandle()`, que revienta con closures.

---

## Cómo correr

```sh
# Primera vez / tras tocar pubspec.yaml — SIEMPRE con --no-example
# (ver docs/known-issues.md, example/ no resuelve en un SDK Dart moderno)
flutter pub get --no-example

# Toda la suite
flutter test

# Un archivo
flutter test test/background_locator_test.dart

# Formatear antes de commitear (ver docs/style.md § 2)
dart format lib/ test/
```
