import 'package:background_locator_2/keys.dart';
import 'package:background_locator_2/settings/android_settings.dart';
import 'package:background_locator_2/settings/locator_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AndroidNotificationSettings', () {
    test('valores default documentados en el constructor', () {
      const settings = AndroidNotificationSettings();

      expect(settings.notificationChannelName, 'Location tracking');
      expect(settings.notificationTitle, 'Start Location Tracking');
      expect(settings.notificationMsg, 'Track location in background');
      expect(settings.notificationIcon, '');
      expect(settings.notificationIconColor, Colors.grey);
      expect(settings.notificationTapCallback, isNull);
    });
  });

  group('AndroidSettings.toMap', () {
    test('mapea los defaults a las claves nativas esperadas', () {
      const settings = AndroidSettings();
      final map = settings.toMap();

      expect(map[Keys.SETTINGS_ACCURACY], LocationAccuracy.NAVIGATION.value);
      expect(map[Keys.SETTINGS_INTERVAL], 5);
      expect(map[Keys.SETTINGS_DISTANCE_FILTER], 0.0);
      expect(map[Keys.SETTINGS_ANDROID_WAKE_LOCK_TIME], 60);
      expect(map[Keys.SETTINGS_ANDROID_LOCATION_CLIENT],
          LocationClient.google.index);
      expect(map[Keys.SETTINGS_ANDROID_NOTIFICATION_CHANNEL_NAME],
          'Location tracking');
    });

    test('mapea valores custom, incluyendo LocationClient.android', () {
      const settings = AndroidSettings(
        accuracy: LocationAccuracy.LOW,
        interval: 15,
        distanceFilter: 10,
        wakeLockTime: 30,
        client: LocationClient.android,
        androidNotificationSettings: AndroidNotificationSettings(
          notificationTitle: 'Título custom',
        ),
      );
      final map = settings.toMap();

      expect(map[Keys.SETTINGS_ACCURACY], LocationAccuracy.LOW.value);
      expect(map[Keys.SETTINGS_INTERVAL], 15);
      expect(map[Keys.SETTINGS_DISTANCE_FILTER], 10.0);
      expect(map[Keys.SETTINGS_ANDROID_WAKE_LOCK_TIME], 30);
      expect(map[Keys.SETTINGS_ANDROID_LOCATION_CLIENT],
          LocationClient.android.index);
      expect(map[Keys.SETTINGS_ANDROID_NOTIFICATION_TITLE], 'Título custom');
    });
  });
}
