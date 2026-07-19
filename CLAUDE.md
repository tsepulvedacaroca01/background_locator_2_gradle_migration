# background_locator_2 (fork) — Guía para Claude

## Qué es este repo

Fork propio (`tsepulvedacaroca01/background_locator_2_gradle_migration`, rama `master`) del
plugin Flutter `background_locator_2` (originalmente de Yukams, con un fork intermedio de
`sultan18kh` para compatibilidad AGP 8+). Se consume como dependencia git directa (`ref: master`)
desde las apps que lo usan para tracking de ubicación en segundo plano, incluso con la app
minimizada o cerrada.

No es una app — es un **plugin Flutter** (Dart + Android Kotlin + iOS Obj-C) publicable en
pub.dev. Cualquier cambio acá solo tiene efecto en el consumidor después de bump del `ref`/commit
en su `pubspec.lock` y `flutter pub get`.

## Lectura obligatoria al iniciar

Antes de tocar código:
1. `docs/architecture.md` — los dos `MethodChannel`, el `FlutterEngine` secundario, el patrón
   Pluggable. Es la base para entender cualquier archivo suelto.
2. `docs/android.md` o `docs/ios.md` según la plataforma que toques — casi todo el código nativo
   real está ahí explicado con su porqué.
3. `docs/known-issues.md` — gotchas ya pisados (algunos con crash real confirmado en producción).
   Revisar antes de tocar `PreferencesManager`, cualquier `catch` en `IsolateHolderService.kt`, o
   el build de Gradle.

Si el cambio toca la API pública Dart (`lib/`) o agrega un argumento/setting nuevo que cruza el
canal, leer `docs/dart-api.md` § "Sincronización de claves" — es el error más fácil de cometer acá
(un typo en una clave no rompe la compilación, rompe en runtime en silencio).

## Stack

- **Dart**: API pública del plugin (`lib/`), sin lógica de negocio — solo arma/parsea los `Map`
  que cruzan el `MethodChannel` y resuelve `CallbackHandle`s.
- **Android**: Kotlin, `minSdk 21`, `compileSdk 36`, JVM target 17. Dependencias nativas propias:
  `play-services-location:21.0.1`, `gson:2.8.6`.
- **iOS**: Objective-C, deployment target 8.0. Sin dependencias nativas propias más allá de
  `Flutter`/`CoreLocation`.
- Sin tests reales (`test/background_locator_test.dart` es un stub sin asserts). No hay CI
  configurado en este repo.

## Arquitectura (resumen — ver docs/architecture.md para el detalle)

```
App Dart (consumidor)
  → BackgroundLocator (lib/background_locator.dart)
    → canal "app.yukams/locator_plugin" (foreground, Dart → nativo)
      → Android: BackgroundLocatorPlugin.kt → IsolateHolderService (foreground service)
      → iOS: BackgroundLocatorPlugin.m → headless FlutterEngine (_headlessRunner)
        → crea un FlutterEngine SECUNDARIO, sin UI
          → ejecuta lib/callback_dispatcher.dart (entrypoint @pragma('vm:entry-point'))
            → registra su propio MethodCallHandler en
              canal "app.yukams/locator_plugin_background" (nativo ↔ isolate)
      ← el nativo empuja cada ubicación / evento init / evento dispose por ese canal background
        → callbackDispatcher() resuelve el callback real del usuario y lo invoca
```

## Convenciones de este repo

- **Toda clave de canal (`Keys`) vive triplicada a mano** — `lib/keys.dart`, Kotlin `Keys.kt`,
  Obj-C `Globals.h`/`Globals.m`. Agregar algo en una sin agregar el mismo string literal en las
  otras dos rompe en runtime sin ningún error visible (`Map[key]` da `null`, no excepción). Ver
  `docs/dart-api.md`.
- Todo callback expuesto al usuario (`callback`, `initCallback`, `disposeCallback`,
  `notificationTapCallback`) tiene que ser top-level/static y `@pragma('vm:entry-point')` — se
  resuelven por `CallbackHandle`, no funcionan como closures.
- El código nativo Android usa mucho `catch (e: Exception) { }` vacío heredado del código
  original — **no repetir ese patrón en código nuevo**. Los dos bugs reales documentados en
  `docs/known-issues.md` (plugins no registrados, `Missing type parameter`) costaron mucho más
  tiempo de diagnosticar por falta de logging en el punto de falla real. Si agregás un `catch`,
  logueá con `Log.e`/`NSLog` aunque sea en el caso "no debería pasar nunca".
- Cambios de compatibilidad de build (AGP/Gradle/Kotlin) van documentados en el `README.md`
  público (§ "AGP 9 / Gradle 9 compatibility") — es lo primero que lee cualquiera que forkee este
  fork y vea el mismo error. No dupliques ese texto en `docs/`, solo referencialo.

## Comandos frecuentes

```sh
# Probar un cambio desde una app consumidora sin publicar: apuntar su pubspec.yaml a un path
# local (path: ../background_locator_2_gradle_migration) o pushear a master y correr, del lado
# de esa app:
flutter pub upgrade background_locator_2   # trae el último commit de `master`

# Compilar el example de este repo
cd example && flutter run

# Ver el ejemplo de uso "canónico" del API completo (init/dispose/notificationTapCallback)
# example/lib/main.dart, example/lib/location_callback_handler.dart
```

## Docs de referencia

- `docs/architecture.md` — los dos `MethodChannel`, flujo completo de arranque, pluggables
- `docs/android.md` — `IsolateHolderService`, `PreferencesManager`, registro de plugins por
  reflexión, `LocationClient` (Google vs Android), reboot
- `docs/ios.md` — headless `FlutterEngine`, `registerPlugins` callback, region monitoring,
  relanzamiento tras kill
- `docs/dart-api.md` — API pública Dart, settings, `LocationDto`, sincronización de claves
- `docs/known-issues.md` — gotchas de este fork, con un crash real confirmado en producción (Gson
  `TypeToken` + R8) y su fix documentado
