import 'package:permission_handler/permission_handler.dart' as ph;

enum CallPermissionResult { granted, denied, permanentlyDenied }

/// Wraps permission_handler so the rest of the app (and tests) never touch
/// the plugin directly.
class PermissionService {
  Future<CallPermissionResult> requestCallPermissions() async {
    final statuses =
        await [ph.Permission.camera, ph.Permission.microphone].request();

    // Android 12+ wants BLUETOOTH_CONNECT for headset routing. Its denial
    // must never block joining a call, so the result is ignored.
    try {
      await ph.Permission.bluetoothConnect.request();
    } catch (_) {}

    final camera = statuses[ph.Permission.camera];
    final microphone = statuses[ph.Permission.microphone];
    if (camera == null || microphone == null) {
      return CallPermissionResult.denied;
    }
    if (camera.isPermanentlyDenied || microphone.isPermanentlyDenied) {
      return CallPermissionResult.permanentlyDenied;
    }
    if (camera.isGranted && microphone.isGranted) {
      return CallPermissionResult.granted;
    }
    return CallPermissionResult.denied;
  }

  Future<void> openSettings() => ph.openAppSettings();
}
