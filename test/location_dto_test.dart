import 'package:background_locator_2/keys.dart';
import 'package:background_locator_2/location_dto.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _rawLocation({
  double latitude = -33.45,
  double longitude = -70.65,
  double accuracy = 5.0,
  double altitude = 520.0,
  double speed = 1.2,
  double speedAccuracy = 0.5,
  double heading = 90.0,
  double time = 1700000000000.0,
  bool isMocked = false,
  String? provider = 'gps',
}) {
  final json = {
    Keys.ARG_LATITUDE: latitude,
    Keys.ARG_LONGITUDE: longitude,
    Keys.ARG_ACCURACY: accuracy,
    Keys.ARG_ALTITUDE: altitude,
    Keys.ARG_SPEED: speed,
    Keys.ARG_SPEED_ACCURACY: speedAccuracy,
    Keys.ARG_HEADING: heading,
    Keys.ARG_TIME: time,
    Keys.ARG_IS_MOCKED: isMocked,
  };

  if (provider != null) {
    json[Keys.ARG_PROVIDER] = provider;
  }

  return json;
}

void main() {
  group('LocationDto.fromJson', () {
    test('parsea todos los campos numéricos y el provider', () {
      final dto = LocationDto.fromJson(_rawLocation());

      expect(dto.latitude, -33.45);
      expect(dto.longitude, -70.65);
      expect(dto.accuracy, 5.0);
      expect(dto.altitude, 520.0);
      expect(dto.speed, 1.2);
      expect(dto.speedAccuracy, 0.5);
      expect(dto.heading, 90.0);
      expect(dto.time, 1700000000000.0);
      expect(dto.provider, 'gps');
    });

    test('provider ausente cae a string vacío, no null', () {
      final dto = LocationDto.fromJson(_rawLocation(provider: null));

      expect(dto.provider, '');
    });

    // Platform.isAndroid (dart:io) refleja el SO real del proceso que corre
    // el test — en `flutter test` (host, no un dispositivo Android) siempre
    // es false, así que isMocked resuelve false sin importar el valor del
    // JSON. Este test documenta ese comportamiento real, no lo que el plugin
    // haría corriendo en un dispositivo Android de verdad.
    test('isMocked resuelve false en el host de test (no es Android)', () {
      final dto = LocationDto.fromJson(_rawLocation(isMocked: true));

      expect(dto.isMocked, isFalse);
    });
  });

  group('LocationDto.toJson', () {
    test('round-trip por fromJson preserva los campos', () {
      final original = LocationDto.fromJson(_rawLocation());
      final roundTripped = LocationDto.fromJson(original.toJson());

      expect(roundTripped.latitude, original.latitude);
      expect(roundTripped.longitude, original.longitude);
      expect(roundTripped.accuracy, original.accuracy);
      expect(roundTripped.provider, original.provider);
      expect(roundTripped.isMocked, original.isMocked);
    });
  });
}
