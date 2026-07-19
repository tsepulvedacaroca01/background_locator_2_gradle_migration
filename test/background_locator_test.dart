import 'package:background_locator_2/background_locator.dart';
import 'package:background_locator_2/keys.dart';
import 'package:background_locator_2/location_dto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

@pragma('vm:entry-point')
void _locationCallback(LocationDto location) {}

void main() {
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

  test('registerLocationUpdate() manda el método y el handle del callback', () async {
    await BackgroundLocator.registerLocationUpdate(_locationCallback);

    expect(lastCall.method, Keys.METHOD_PLUGIN_REGISTER_LOCATION_UPDATE);
    expect(lastCall.arguments[Keys.ARG_CALLBACK], isA<int>());
  });

  test('unRegisterLocationUpdate() invoca el método correcto', () async {
    await BackgroundLocator.unRegisterLocationUpdate();

    expect(lastCall.method, Keys.METHOD_PLUGIN_UN_REGISTER_LOCATION_UPDATE);
  });

  test('isRegisterLocationUpdate() invoca el método y devuelve el bool del canal', () async {
    mockResult = false;

    final result = await BackgroundLocator.isRegisterLocationUpdate();

    expect(lastCall.method, Keys.METHOD_PLUGIN_IS_REGISTER_LOCATION_UPDATE);
    expect(result, isFalse);
  });

  test('isServiceRunning() invoca el método y devuelve el bool del canal', () async {
    mockResult = true;

    final result = await BackgroundLocator.isServiceRunning();

    expect(lastCall.method, Keys.METHOD_PLUGIN_IS_SERVICE_RUNNING);
    expect(result, isTrue);
  });

  group('updateNotificationText', () {
    test('solo incluye los campos no nulos', () async {
      await BackgroundLocator.updateNotificationText(title: 'Nuevo título');

      expect(lastCall.method, Keys.METHOD_PLUGIN_UPDATE_NOTIFICATION);
      expect(lastCall.arguments, {Keys.SETTINGS_ANDROID_NOTIFICATION_TITLE: 'Nuevo título'});
    });

    test('incluye los tres campos si los tres se pasan', () async {
      await BackgroundLocator.updateNotificationText(
        title: 'Título',
        msg: 'Mensaje',
        bigMsg: 'Mensaje largo',
      );

      expect(lastCall.arguments, {
        Keys.SETTINGS_ANDROID_NOTIFICATION_TITLE: 'Título',
        Keys.SETTINGS_ANDROID_NOTIFICATION_MSG: 'Mensaje',
        Keys.SETTINGS_ANDROID_NOTIFICATION_BIG_MSG: 'Mensaje largo',
      });
    });
  });
}
