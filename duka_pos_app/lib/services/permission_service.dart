// The permissions this till needs, and whether it has them.
//
// ## WHY THE APP ASKS, IN ONE PLACE
//
// A permission asked for at the moment it is needed is a permission prompt
// that arrives in the middle of a sale, with a queue waiting: the shopkeeper
// opens the scanner and gets a system dialog about the camera while a
// customer is at the counter. The owner of a shop answers that question once,
// during setup, where they are not in the middle of anything.
//
// So the app ASKS, in one step, after the walkthrough — and each permission
// carries the reason it is wanted, in the shop's language, so the answer is
// informed.
//
// ## WHAT IS ASKED, AND WHAT IS NOT
//
// The camera, and Bluetooth. That is the whole list, and the list is short on
// purpose.
//
//   * CAMERA — scanning barcodes, and photographing a product. A shop with a
//     wedge scanner and no camera is a perfectly good shop, so this is
//     skippable and the app works without it.
//   * BLUETOOTH — the receipt printer.
//
// NOT asked, and deliberately so:
//
//   * NOTIFICATIONS — the app has no notification feature. A permission for
//     something the app does not do is a permission the owner refuses for
//     nothing, and a refusal teaches them to refuse.
//   * LOCATION — the app never derives a place from a radio. A till that
//     wanted location would be a till asking for something a shop should not
//     have to explain.
//   * STORAGE / PHOTOS — reading the gallery goes through the system photo
//     picker, which needs no permission at all.
//
// ## WHY THE CHANNEL IS OWNED OUTRIGHT
//
// The `permission_handler` pub package would do this in a few lines. The
// printer's Bluetooth permission is already owned outright in
// `PrinterChannel.kt` for the same reason — the package it wanted was
// discontinued, and a till should not carry a dependency graph for one
// question — so the camera permission is owned the same way.
//
// The Bluetooth half is NOT duplicated here: the printer channel already owns
// `BLUETOOTH_CONNECT`, and asking for the same permission from two channels is
// two code paths that can disagree about whether it is held. This service
// composes: the camera comes from the permission channel, Bluetooth comes
// from the printer service that already knows how to ask for it.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'printer/esc_pos_printer.dart';
import 'printer/printer_service.dart';

/// One permission the till can hold, refused, or never have been asked about.
enum TillPermission {
  /// The camera: scanning barcodes and photographing products.
  camera,

  /// Bluetooth: the receipt printer.
  bluetooth,
}

/// Where a permission stands right now.
enum PermissionState {
  /// Never asked. The app has not raised a prompt for it on this device.
  notAsked,

  /// Held.
  granted,

  /// Refused, and the app may ask again.
  refused,

  /// Refused with "don't ask again": only the system Settings screen can undo
  /// it, so the app must not ask again.
  permanentlyDenied,
}

/// The permissions the till needs, and how to ask for them.
abstract class PermissionService {
  /// Where [permission] stands.
  Future<PermissionState> state(TillPermission permission);

  /// Raises the system prompt for [permission] and answers whether it was
  /// granted.
  Future<bool> request(TillPermission permission);
}

/// The real service, over a method channel.
class PlatformPermissionService implements PermissionService {
  PlatformPermissionService({MethodChannel? channel, PrinterService? printer})
      : _channel = channel ?? const MethodChannel(channelName),
        _printer = printer ?? EscPosPrinter();

  static const channelName = 'duka_pos/permissions';

  final MethodChannel _channel;

  /// The printer, for the Bluetooth permission it already owns.
  final PrinterService _printer;

  @override
  Future<PermissionState> state(TillPermission permission) async {
    switch (permission) {
      case TillPermission.camera:
        return _cameraState();
      case TillPermission.bluetooth:
        return _bluetoothState();
    }
  }

  @override
  Future<bool> request(TillPermission permission) async {
    switch (permission) {
      case TillPermission.camera:
        return await _invoke<bool>('requestCameraPermission') ?? false;
      case TillPermission.bluetooth:
        try {
          return await _printer.requestPermission();
        } on Object {
          // A printer service that cannot reach its channel cannot ask for the
          // permission. That is "not granted", not a crash: the till carries on
          // without a printer.
          return false;
        }
    }
  }

  Future<PermissionState> _cameraState() async {
    final bool? held = await _invoke<bool>('hasCameraPermission');
    if (held == null) return PermissionState.notAsked;
    if (held) return PermissionState.granted;
    final bool? denied =
        await _invoke<bool>('isCameraPermissionPermanentlyDenied');
    return denied == true
        ? PermissionState.permanentlyDenied
        : PermissionState.refused;
  }

  Future<PermissionState> _bluetoothState() async {
    try {
      if (await _printer.hasPermission()) return PermissionState.granted;
      if (await _printer.isPermissionPermanentlyDenied()) {
        return PermissionState.permanentlyDenied;
      }
      return PermissionState.refused;
    } on Object {
      return PermissionState.notAsked;
    }
  }

  Future<T?> _invoke<T>(String method) async {
    try {
      return await _channel.invokeMethod<T>(method);
    } on PlatformException catch (error) {
      debugPrint('Permission channel error: $error');
      return null;
    } on MissingPluginException catch (error) {
      // No native side registered: a desktop run or a test. Reported as "not
      // asked" rather than thrown, so the permissions step degrades to a
      // screen that explains itself instead of a crash.
      debugPrint('Permission channel unavailable: $error');
      return null;
    }
  }
}
