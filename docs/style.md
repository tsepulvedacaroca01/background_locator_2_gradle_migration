# Estilo de código

Convenciones verificadas contra el código real de este repo (`lib/`, `test/`) — no inventadas.
Documenta qué tan consistente está cada regla hoy, para que quede claro qué es una convención ya
establecida y qué es un objetivo a aplicar de a poco en código nuevo. `dart format` no impone la
mayoría de esto — hay que aplicarlo a mano.

---

## 1. Líneas en blanco alrededor de bloques de control

Línea en blanco antes de `if`/`return` salvo que sea la primera instrucción del cuerpo, o la línea
anterior ya termine en `{`. Línea en blanco después de que un bloque `{ ... }` termina y el código
vuelve a un nivel de indentación menor, salvo que la siguiente línea sea `else`/`catch`/`finally`.

```dart
// ✓ Correcto (lib/utils/settings_util.dart)
final args = _getCommonArgumentsMap(...);

if (Platform.isAndroid) {
  args.addAll(_getAndroidArgumentsMap(androidSettings));
} else if (Platform.isIOS) {
  args.addAll(_getIOSArgumentsMap(iosSettings));
}

return args;
```

**Estado:** aplicado en todo `lib/` (rama `major-update`) — la única brecha real encontrada
(`_getCommonArgumentsMap`, mismo archivo: dos `if` hermanos consecutivos sin línea en blanco entre
ellos) se corrigió.

---

## 2. Trailing comma en llamadas/constructores/colecciones multilínea

Toda llamada, constructor o literal de colección que se parte en más de una línea lleva coma final
en el último argumento/elemento.

```dart
// ✓ Correcto
return LocationDto._(
  json[Keys.ARG_LATITUDE],
  ...
  json[Keys.ARG_PROVIDER] ?? '',
);
```

`dart format` la refuerza en la mayoría de los casos (correr `dart format lib/ test/` antes de
commitear cualquier cambio), pero **no** es garantía absoluta: si una colección multilínea ya cabe
en el ancho de columna sin la coma final, `dart format` la deja como está sin agregarla — no confiar
en que "`dart format` no tocó nada" signifique "ya está bien", revisar a mano el último elemento de
cualquier colección/llamada multilínea que edites.

**Estado:** 0 violaciones — la única brecha real encontrada (`AndroidSettings.toMap()`, última
entrada del `Map` sin coma final) se corrigió en la rama `major-update`.

---

## 3. Doc comments `///` — API pública densa, en inglés

A diferencia de un uso minoritario, acá **todo constructor de una clase de settings pública**
(`AndroidSettings`, `AndroidNotificationSettings`, `IOSSettings`, `LocatorSettings`) documenta cada
parámetro con su propio bloque `///`, en inglés — es la superficie pública de un plugin en pub.dev,
consumida por gente que no necesariamente lee español:

```dart
/// [accuracy] The accuracy of location, Default is max accuracy NAVIGATION.
///
/// [interval] Interval of retrieving location update in second. Only applies for android. Default is 5 second.
///
/// [distanceFilter] distance in meter to trigger location update, Default is 0 meter.
const AndroidSettings({...});
```

**Regla**: si agregás un parámetro nuevo a una clase de `lib/settings/`, documentalo con el mismo
patrón (`/// [nombreParam] descripción.`, en inglés). No lo extiendas a métodos internos/privados
o a `lib/utils/` — ahí no hay este patrón hoy y el nombre ya es suficientemente explícito.

**Estado:** 100% consistente en las 4 clases públicas de `lib/settings/`.

---

## 4. Idioma — separar API pública de documentación interna

Este repo mezcla dos audiencias distintas, y cada una tiene su propio idioma establecido:

| Qué | Idioma | Por qué |
|---|---|---|
| Doc comments `///` de la API pública Dart (`lib/settings/`) | Inglés | Paquete pub.dev, consumido por cualquiera |
| Comentarios `//` heredados del código original (Kotlin/Obj-C, autores previos) | Inglés | No reescribir el contexto de otro autor solo por consistencia |
| Comentarios `//` nuevos de este fork (ver `IsolateHolderExtension.kt`) | Español | Convención de quien mantiene este fork hoy |
| `docs/*.md`, `CLAUDE.md`, mensajes de commit | Español | Documentación interna del mantenedor, no de la audiencia de pub.dev |

No mezclar los dos idiomas dentro del mismo bloque de comentario — si estás agregando una
explicación nueva a un bloque de comentarios en inglés ya existente, seguí en inglés para no
partir el bloque a la mitad.

---

## 5. Nombrado de archivos

`snake_case` siempre. Verificado sobre los 9 archivos de `lib/` y los 6 de `test/`
(`android_settings.dart`, `settings_util.dart`, `background_locator_test.dart`, etc.) — sin
excepciones.

---

## 6. Longitud de línea

Sin regla de lint configurada (no hay `analysis_options.yaml` en la raíz de este repo en
absoluto). Apoyate en el ancho por defecto de `dart format` (80 columnas) — correlo antes de cada
commit, no hace falta cortar líneas a mano si `dart format` ya las dejó así.

---

## 7. Orden de imports

Tres bloques separados por línea en blanco, cada uno alfabetizado por ruta completa, sin imports
relativos para los propios módulos del paquete (sigue el lint `always_use_package_imports` de
`package:lints`/`flutter_lints` aunque no esté forzado acá):

```dart
import 'dart:async';                                        // 1. dart:* — alfabetizado

import 'package:flutter/services.dart';                      // 2. paquetes externos —
import 'package:flutter/widgets.dart';                        //    alfabetizado

import 'package:background_locator_2/keys.dart';              // 3. package:background_locator_2/...
import 'package:background_locator_2/location_dto.dart';      //    alfabetizado por ruta completa
```

**Estado:** aplicado en toda `lib/` (rama `major-update`) — antes había imports relativos
(`import 'keys.dart';`) mezclados con `package:background_locator_2/...` absoluto, incluso dentro
de un mismo archivo (`lib/background_locator.dart`). No reordenar imports de un archivo que no
estás tocando solo por esto si en algún momento se vuelve a desviar.

---

## Nota — código nativo (Android/iOS)

El código Kotlin (`android/src/main/kotlin/`) y Objective-C (`ios/Classes/`) sigue el estilo que
ya tenía antes de este fork (4 espacios de indentación, sin linter Kotlin/SwiftLint configurado en
este repo). No hay reglas de estilo nativo verificadas para documentar acá más allá de la
convención de idioma de la sección 4 — si en algún momento se agrega un linter nativo
(`ktlint`/`detekt`), documentar sus reglas reales en este archivo, no antes.
