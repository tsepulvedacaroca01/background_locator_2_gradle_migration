# Looking for Maintainers
This project is no longer actively maintained. If you are interested in becoming a maintainer, please open an issue or contact me directly !

# background_locator_2 ! [![pub package](https://img.shields.io/pub/v/background_locator_2.svg)](https://pub.dartlang.org/packages/background_locator_2) ![](https://img.shields.io/github/contributors/Yukams/background_locator_fixed) ![](https://img.shields.io/github/license/Yukams/background_locator_fixed)

This package is a V2 of the background_locator package, fixing it and making it work for the newest versions of Flutter. Please read the wiki in order to make this plugin work with flutter 3.x.

A Flutter plugin for getting location updates even when the app is killed.

## Fork Information

This is a fork of the original background_locator_2 plugin with the following improvements:

- Added compatibility with Android Gradle Plugin 8.0+
- Fixed JVM target compatibility issues
- Updated Gradle and Kotlin dependencies
- Added proper namespace to Android build.gradle

### AGP 9 / Gradle 9 compatibility (this fork's `master`)

Consuming this plugin from a project on Android Gradle Plugin 9.x / Gradle 9.x (e.g. a current
Flutter template) required three additional fixes on top of the ones above — none of these change
the plugin's public Dart API, only its Android build config and one internal Kotlin file:

1. **`android/build.gradle`** — removed the legacy `buildscript { repositories { jcenter() } ... }`
   block declaring its own AGP 7.3.0/Kotlin 1.7.20 classpath. `jcenter()` no longer exists as a
   method on modern Gradle's `RepositoryHandler` (JCenter shut down in 2022) — any consumer on a
   recent Gradle version fails immediately with `Could not find method jcenter()` while evaluating
   this module, before even reaching the plugin's own code. Replaced with a plain `plugins { id
   'com.android.library'; id 'org.jetbrains.kotlin.android' }` block that resolves its AGP/Kotlin
   version from whatever the consuming app's root `pluginManagement`/`settings.gradle.kts` already
   declares — the standard approach for Flutter plugin modules today.
2. **Same file** — the `plugins {}` block must be the *first* statement in the file (only
   `buildscript {}`/`pluginManagement {}`/other `plugins {}` blocks may precede it). Gradle 9
   enforces this; a `group`/`version` assignment before it fails with `only buildscript {},
   pluginManagement {} and other plugins {} script blocks are allowed before plugins {} blocks`.
3. **`android/src/main/kotlin/.../provider/LocationParserUtil.kt`** — `hashMapOf(...)` calls
   declared to return `HashMap<Any, Any>` need the type argument spelled out explicitly
   (`hashMapOf<Any, Any>(...)`); newer Kotlin compilers infer a narrower type from the arguments'
   common supertype instead of the declared return type, which no longer satisfies it. Also, one
   of those maps put `location.provider` (`String?`) into a non-nullable `Any` value — needs a
   `?? ''` fallback.

If you fork this fork and see one of the errors above, these three fixes are the whole diff.

### App plugins not registered on the background `FlutterEngine` (Android)

The background isolate runs on a separate `FlutterEngine(context)` created by
`IsolateHolderService`/`startLocatorService`. Upstream, this engine never registered the consuming
app's Flutter plugins (`GeneratedPluginRegistrant`) — any plugin with a platform channel used inside
your callback (`shared_preferences`, `path_provider`, etc.) throws `MissingPluginException`, silently
if your callback doesn't log the caught exception. This fork calls
`io.flutter.plugins.GeneratedPluginRegistrant.registerWith(engine)` via reflection right after
creating the engine (`IsolateHolderExtension.kt`, `registerAppPlugins`) — reflection because that
class is generated inside the consuming app's own module, not a compile-time dependency of this
plugin module. Look for `IsolateHolderExtension: App plugins registered on background engine OK` in
logcat to confirm it worked (or the `Failed to register...` line, which now also logs `Throwable`
instead of just `Exception` — `Class.forName`/`invoke` can throw `Error` subclasses too, which used
to escape silently and abort the whole engine startup before ever running your Dart callback).

### `BackgroundLocator.initialize()` is required before `registerLocationUpdate()`

This one lives entirely on the Dart side, but it's the #1 reason "nothing happens" after everything
above is fixed: `initialize()` is what persists the `callbackDispatcher` handle into native
`SharedPreferences`. Skip it and `IsolateHolderService` logs `Fatal: failed to find callback` and
returns *before* calling `executeDartCallback` — your background isolate never starts, so no print
statement in your callback ever runs, not even the first line. Always call:

```dart
await BackgroundLocator.initialize();
await BackgroundLocator.registerLocationUpdate(yourCallback, ...);
```

### `FOREGROUND_SERVICE_LOCATION` required on Android 14+ (`targetSdk >= 34`)

Starting with Android 14, a foreground service declared with `foregroundServiceType="location"`
(this plugin's `IsolateHolderService`) needs the caller app to declare
`android.permission.FOREGROUND_SERVICE_LOCATION` in its manifest, in addition to
`ACCESS_FINE_LOCATION`/`ACCESS_COARSE_LOCATION`. Without it, `IsolateHolderService.onCreate()`
crashes as soon as `registerLocationUpdate()` is called — even with the location permissions
already granted at runtime:

```
SecurityException: Starting FGS with type location ... requires permissions: all of the
permissions allOf=true [android.permission.FOREGROUND_SERVICE_LOCATION] any of the permissions
allOf=false [android.permission.ACCESS_COARSE_LOCATION, android.permission.ACCESS_FINE_LOCATION]
```

Add this to your app's `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
```

### Gson/R8 crash fixed automatically for consumers that minify (Android)

Older versions of this fork required consumers building with R8/ProGuard enabled to copy a set of
Gson `TypeToken` keep rules into their own `android/app/proguard-rules.pro`, or hit a runtime
crash (`RuntimeException: Missing type parameter.`) as soon as the background service started.
This fork now ships `android/consumer-rules.pro`, applied automatically to any consumer via
Gradle's `consumerProguardFiles` — no manual ProGuard setup needed anymore. If your app already had
this workaround copied by hand, it's now redundant and safe to remove.

### `initCallback` fix — was silently never firing

`registerLocationUpdate(..., initCallback: ...)` declared its parameter as `Map<String, dynamic>`,
but the actual value handed to it at runtime was whatever `StandardMethodCodec` decodes a platform
channel `Map` into (`Map<Object?, Object?>`) — not assignable to `Map<String, dynamic>`, so the
callback threw a `TypeError` inside an unawaited `Future` and silently never ran. Fixed — callers
using `initCallback` with the documented `Map<String, dynamic>` signature now receive it correctly.

## Usage with this fork

To use this fork in your Flutter project, add the following to your `pubspec.yaml`:

```yaml
dependencies:
  background_locator_2:
    git:
      url: git@github.com:tsepulvedacaroca01/background_locator_2_gradle_migration.git
      ref: master
```

![demo](https://raw.githubusercontent.com/RomanJos/background_locator/master/demo.gif)

Refer to [wiki](https://github.com/Yukams/background_locator_fixed/wiki) page for install and setup instruction or jump to specific subject with below links:

* [Installation](https://github.com/Yukams/background_locator_fixed/wiki/Installation)
* [Setup](https://github.com/Yukams/background_locator_fixed/wiki/Setup)
* [How to use](https://github.com/Yukams/background_locator_fixed/wiki/How-to-use)
* [Use other plugins in callback](https://github.com/Yukams/background_locator_fixed/wiki/Use-other-plugins-in-callback)
* [Stop on app terminate](https://github.com/Yukams/background_locator_fixed/wiki/Stop-on-app-terminate)
* [LocationSettings options](https://github.com/Yukams/background_locator_fixed/wiki/LocationSettings-options)
* [Restart service on device reboot (Android only)](https://github.com/Yukams/background_locator_fixed/wiki/Restart-service-on-device-reboot)

##  License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details

## Contributor
Thanks to all who contributed on this plugin to fix bugs and adding new feature, including:
* [Rekab](https://github.com/rekabhq) (creator of V1)
* [Gerardo Ibarra](https://github.com/gpibarra)
* [RomanJos](https://github.com/RomanJos)
* [Marcelo Henrique Neppel](https://github.com/marceloneppel)
* [Sultan Khan](https://github.com/sultan18kh) (creator of fork)
