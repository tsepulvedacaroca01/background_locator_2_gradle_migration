import 'dart:ui';

import 'package:background_locator_2/callback_dispatcher.dart';
import 'package:background_locator_2/keys.dart';
import 'package:background_locator_2/location_dto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

LocationDto? _receivedLocation;

@pragma('vm:entry-point')
void _locationCallback(LocationDto location) {
  _receivedLocation = location;
}

bool _notificationCallbackCalled = false;

@pragma('vm:entry-point')
void _notificationCallback() {
  _notificationCallbackCalled = true;
}

Map<String, dynamic>? _receivedInitData;

@pragma('vm:entry-point')
void _initCallback(Map<String, dynamic> data) {
  _receivedInitData = data;
}

bool _disposeCallbackCalled = false;

@pragma('vm:entry-point')
void _disposeCallback() {
  _disposeCallbackCalled = true;
}

Map<String, dynamic> _rawLocation() {
  return {
    Keys.ARG_LATITUDE: -33.45,
    Keys.ARG_LONGITUDE: -70.65,
    Keys.ARG_ACCURACY: 5.0,
    Keys.ARG_ALTITUDE: 520.0,
    Keys.ARG_SPEED: 1.2,
    Keys.ARG_SPEED_ACCURACY: 0.5,
    Keys.ARG_HEADING: 90.0,
    Keys.ARG_TIME: 1700000000000.0,
    Keys.ARG_IS_MOCKED: false,
    Keys.ARG_PROVIDER: 'gps',
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const backgroundChannel = MethodChannel(Keys.BACKGROUND_CHANNEL_ID);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  // callbackDispatcher() termina llamando _backgroundChannel.invokeMethod(
  // METHOD_SERVICE_INITIALIZED) — sin un mock handler para esa llamada saliente,
  // el binding de test la deja sin resolver (no afecta los asserts, pero
  // ensucia el log). La simulamos como un no-op.
  messenger.setMockMethodCallHandler(backgroundChannel, (call) async => null);

  // Simula una llamada entrante del lado nativo, tal como la manda
  // IsolateHolderService.sendLocationEvent()/BackgroundLocatorPlugin.onNewIntent()
  // (BCM_NOTIFICATION_CLICK) o los Pluggable (BCM_INIT/BCM_DISPOSE) — es el
  // mismo mecanismo que dispara un tap real en la notificación en un
  // dispositivo, solo que acá el "nativo" somos nosotros armando el MethodCall
  // a mano.
  Future<void> simulateNativeCall(
      String method, Map<Object?, Object?> arguments) async {
    final data =
        backgroundChannel.codec.encodeMethodCall(MethodCall(method, arguments));
    await messenger.handlePlatformMessage(
        Keys.BACKGROUND_CHANNEL_ID, data, (_) {});
  }

  setUp(() {
    _receivedLocation = null;
    _notificationCallbackCalled = false;
    _receivedInitData = null;
    _disposeCallbackCalled = false;

    callbackDispatcher();
  });

  test(
      'BCM_SEND_LOCATION invoca el callback de ubicación con el LocationDto parseado',
      () async {
    final handle =
        PluginUtilities.getCallbackHandle(_locationCallback)!.toRawHandle();

    await simulateNativeCall(Keys.BCM_SEND_LOCATION, {
      Keys.ARG_CALLBACK: handle,
      Keys.ARG_LOCATION: _rawLocation(),
    });

    expect(_receivedLocation, isNotNull);
    expect(_receivedLocation!.latitude, -33.45);
    expect(_receivedLocation!.provider, 'gps');
  });

  // Es la garantía real de que "tocar la notificación" hace algo — el toque
  // en sí lo maneja BackgroundLocatorPlugin.onNewIntent() del lado Android
  // (no testeable acá, ver docs/testing.md), pero la resolución del handle y
  // la invocación del callback del usuario son responsabilidad de este
  // dispatcher, y es exactamente lo que este test verifica.
  test(
      'BCM_NOTIFICATION_CLICK invoca el callback registrado al tocar la notificación',
      () async {
    final handle =
        PluginUtilities.getCallbackHandle(_notificationCallback)!.toRawHandle();

    await simulateNativeCall(Keys.BCM_NOTIFICATION_CLICK, {
      Keys.ARG_NOTIFICATION_CALLBACK: handle,
    });

    expect(_notificationCallbackCalled, isTrue);
  });

  test(
      'BCM_INIT invoca initCallback con la data inicial (InitPluggable.onServiceStart)',
      () async {
    final handle =
        PluginUtilities.getCallbackHandle(_initCallback)!.toRawHandle();

    await simulateNativeCall(Keys.BCM_INIT, {
      Keys.ARG_INIT_CALLBACK: handle,
      Keys.ARG_INIT_DATA_CALLBACK: {'countInit': 1},
    });

    expect(_receivedInitData, {'countInit': 1});
  });

  test('BCM_DISPOSE invoca disposeCallback (DisposePluggable.onServiceDispose)',
      () async {
    final handle =
        PluginUtilities.getCallbackHandle(_disposeCallback)!.toRawHandle();

    await simulateNativeCall(Keys.BCM_DISPOSE, {
      Keys.ARG_DISPOSE_CALLBACK: handle,
    });

    expect(_disposeCallbackCalled, isTrue);
  });
}
