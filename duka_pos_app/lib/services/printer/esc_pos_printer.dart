import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'printer_service.dart';

/// Bluetooth ESC/POS printing over a thin Kotlin `MethodChannel`.
///
/// The `bluetooth_printers` pub package is discontinued on pub.dev and pulls a
/// transitive `rxdart`/`shelf` graph this app does not otherwise have, so the
/// channel is owned outright: roughly 150 lines of Kotlin over
/// `BluetoothSocket` in `PrinterChannel.kt`, and the [PrinterService] seam means
/// swapping it is a one-line change.
///
/// Every method returns a plain value and never throws across the channel
/// boundary; platform failures come back as a [PrinterException] so the screen
/// above can choose the message.
class EscPosPrinter implements PrinterService {
  EscPosPrinter({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'duka_pos/printer';

  final MethodChannel _channel;

  Future<T?> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (error) {
      throw PrinterException(
        _failureFor(error.code),
        error.message,
      );
    } on MissingPluginException catch (error) {
      // No native side registered: a desktop run or a test. Reported as
      // unavailable rather than thrown, so a till with no printer degrades to
      // "couldn't print" instead of a crash.
      debugPrint('Printer channel unavailable: $error');
      throw const PrinterException(PrinterFailure.unavailable);
    }
  }

  @override
  Future<bool> isAvailable() async =>
      await _invoke<bool>('isAvailable') ?? false;

  @override
  Future<bool> hasPermission() async =>
      await _invoke<bool>('hasPermission') ?? false;

  @override
  Future<bool> requestPermission() async =>
      await _invoke<bool>('requestPermission') ?? false;

  @override
  Future<bool> isPermissionPermanentlyDenied() async =>
      await _invoke<bool>('isPermissionPermanentlyDenied') ?? false;

  @override
  Future<List<PrinterDevice>> pairedDevices() async {
    final raw = await _invoke<List<Object?>>('pairedDevices') ?? const [];
    final devices = <PrinterDevice>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final address = entry['address'];
      if (address is! String || address.isEmpty) continue;
      devices.add(PrinterDevice(
        address: address,
        name: entry['name'] is String ? entry['name'] as String : '',
      ));
    }
    return devices;
  }

  @override
  Future<bool> pair(String address) async =>
      await _invoke<bool>('pair', {'address': address}) ?? false;

  @override
  Future<bool> isPaired(String address) async =>
      await _invoke<bool>('isPaired', {'address': address}) ?? false;

  @override
  Future<void> connect(String address, {Duration timeout = const Duration(seconds: 8)}) async {
    await _invoke<bool>('connect', {
      'address': address,
      'timeoutMs': timeout.inMilliseconds,
    });
  }

  @override
  Future<void> send(Uint8List bytes) async {
    await _invoke<bool>('send', {'bytes': bytes});
  }

  @override
  Future<bool> isConnected() async =>
      await _invoke<bool>('isConnected') ?? false;

  @override
  Future<void> disconnect() async {
    await _invoke<bool>('disconnect');
  }

  @override
  Future<void> dispose() => disconnect();

  /// The Kotlin side reports failures with a stable string code rather than a
  /// message, so a message change on the platform side cannot silently change
  /// what the operator is told.
  static PrinterFailure _failureFor(String code) => switch (code) {
        'permission_denied' => PrinterFailure.permissionDenied,
        'permission_permanently_denied' =>
          PrinterFailure.permissionPermanentlyDenied,
        'not_paired' => PrinterFailure.notPaired,
        'connect_failed' => PrinterFailure.connectFailed,
        'print_failed' => PrinterFailure.printFailed,
        'unavailable' => PrinterFailure.unavailable,
        _ => PrinterFailure.printFailed,
      };
}