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
