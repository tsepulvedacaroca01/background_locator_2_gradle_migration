import 'package:background_locator_2/keys.dart';
import 'package:background_locator_2/settings/ios_settings.dart';
import 'package:background_locator_2/settings/locator_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IOSSettings.toMap', () {
    test('mapea los defaults a las claves nativas esperadas', () {
      const settings = IOSSettings();
      final map = settings.toMap();

      expect(map[Keys.SETTINGS_ACCURACY], LocationAccuracy.NAVIGATION.value);
      expect(map[Keys.SETTINGS_DISTANCE_FILTER], 0.0);
      expect(
          map[Keys.SETTINGS_IOS_SHOWS_BACKGROUND_LOCATION_INDICATOR], isFalse);
      expect(map[Keys.SETTINGS_IOS_STOP_WITH_TERMINATE], isFalse);
    });

    test('mapea valores custom', () {
      const settings = IOSSettings(
        accuracy: LocationAccuracy.BALANCED,
        distanceFilter: 25,
        showsBackgroundLocationIndicator: true,
        stopWithTerminate: true,
      );
      final map = settings.toMap();

      expect(map[Keys.SETTINGS_ACCURACY], LocationAccuracy.BALANCED.value);
      expect(map[Keys.SETTINGS_DISTANCE_FILTER], 25.0);
      expect(
          map[Keys.SETTINGS_IOS_SHOWS_BACKGROUND_LOCATION_INDICATOR], isTrue);
      expect(map[Keys.SETTINGS_IOS_STOP_WITH_TERMINATE], isTrue);
    });
  });
}
