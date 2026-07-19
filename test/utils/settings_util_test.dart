import 'package:background_locator_2/keys.dart';
import 'package:background_locator_2/location_dto.dart';
import 'package:background_locator_2/utils/settings_util.dart';
import 'package:flutter_test/flutter_test.dart';

void _callback(LocationDto location) {}
void _initCallback(Map<String, dynamic> data) {}
void _disposeCallback() {}

void main() {
  group('SettingsUtil.getArgumentsMap', () {
    test('siempre incluye el handle del callback principal', () {
      final args = SettingsUtil.getArgumentsMap(callback: _callback);

      expect(args[Keys.ARG_CALLBACK], isA<int>());
    });

    test('initCallback/disposeCallback ausentes no agregan sus claves', () {
      final args = SettingsUtil.getArgumentsMap(callback: _callback);

      expect(args.containsKey(Keys.ARG_INIT_CALLBACK), isFalse);
      expect(args.containsKey(Keys.ARG_DISPOSE_CALLBACK), isFalse);
    });

    test('initCallback/disposeCallback presentes agregan sus handles', () {
      final args = SettingsUtil.getArgumentsMap(
        callback: _callback,
        initCallback: _initCallback,
        disposeCallback: _disposeCallback,
      );

      expect(args[Keys.ARG_INIT_CALLBACK], isA<int>());
      expect(args[Keys.ARG_DISPOSE_CALLBACK], isA<int>());
    });

    test('initDataCallback ausente (null) no agrega su clave', () {
      final args = SettingsUtil.getArgumentsMap(callback: _callback);

      expect(args.containsKey(Keys.ARG_INIT_DATA_CALLBACK), isFalse);
    });

    test('initDataCallback presente se agrega tal cual', () {
      final args = SettingsUtil.getArgumentsMap(
        callback: _callback,
        initDataCallback: const {'countInit': 1},
      );

      expect(args[Keys.ARG_INIT_DATA_CALLBACK], {'countInit': 1});
    });

    // Platform.isAndroid/Platform.isIOS (dart:io) reflejan el SO real del
    // proceso que corre el test — en el host de `flutter test` (Linux/macOS/
    // Windows del desarrollador) ninguno de los dos es true, así que ninguna
    // rama de _getAndroidArgumentsMap/_getIOSArgumentsMap corre acá. Este
    // test documenta esa limitación real en vez de simularla: el mapa nunca
    // incluye ARG_SETTINGS fuera de un dispositivo/emulador real.
    test('no agrega settings de plataforma en el host de test', () {
      final args = SettingsUtil.getArgumentsMap(callback: _callback);

      expect(args.containsKey(Keys.ARG_SETTINGS), isFalse);
    });
  });
}
