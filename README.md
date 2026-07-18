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
