import 'dart:typed_data';

/// A Bluetooth device the till can see.
class PrinterDevice {
  const PrinterDevice({required this.name, required this.address});

  final String name;
  final String address;

  /// Shown in the pairing list. A printer that advertises no name still has an
  /// address, and that is enough to pair with — refusing to list it would hide
  /// the cheapest printers on the market.
  String get label => name.trim().isEmpty ? address : name.trim();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PrinterDevice && other.address == address;

  @override
  int get hashCode => address.hashCode;

  @override
  String toString() => '$label ($address)';
}

/// Why a print attempt did not produce paper.
///
/// A typed enum rather than a message string, because the caller has to
/// choose *what to offer the operator* — a settings shortcut for a permission
/// problem, a retry for a dropped link, nothing at all for a printer that is
/// switched off in settings.
enum PrinterFailure {
  /// The shop has not turned printing on. Not an error; never surfaced.
  disabled,

  /// The handset has no Bluetooth radio, or it is off.
  unavailable,

  /// The app has not been granted the runtime Bluetooth permission.
  permissionDenied,

  /// Permission was refused with "don't ask again", so only Settings can fix it.
  permissionPermanentlyDenied,

  /// No configured printer, or it is not paired with this handset.
  notPaired,

  /// The link could not be opened inside the timeout.
  connectFailed,

  /// The link dropped, or the write failed. The usual cause is a printer that
  /// powered itself off between sales.
  printFailed,
}

/// A failure that the operator can be told something specific about.
class PrinterException implements Exception {
  const PrinterException(this.failure, [this.detail]);

  final PrinterFailure failure;

  /// Platform-level detail for the log. Never shown to the operator: a raw
  /// `BluetoothSocket` error is noise to a shop owner.
  final String? detail;

  /// True when the operator has to change something themselves — a permission
  /// or a pairing — rather than simply trying again.
  bool get needsUserAction =>
      failure == PrinterFailure.permissionDenied ||
      failure == PrinterFailure.permissionPermanentlyDenied ||
      failure == PrinterFailure.notPaired;

  @override
  String toString() =>
      'PrinterException(${failure.name}${detail == null ? '' : ': $detail'})';
}

/// The seam between the app and however paper actually gets out of the till.
///
/// Hardware sits behind this so it is swappable and so every screen above it
/// is testable without a device — the same reason [InventoryBackupRequest] exists
/// on the Excel export. The shipped implementation talks to a small Kotlin
/// `MethodChannel` over `BluetoothSocket`; the abandoned `bluetooth_printers`
/// pub package was the alternative and is discontinued, so the channel is owned
/// outright rather than inherited from an unmaintained plugin.
abstract class PrinterService {
  /// True when the handset can print at all: a Bluetooth radio exists and is
  /// switched on.
  Future<bool> isAvailable();

  /// Whether the app holds the runtime Bluetooth permission.
  Future<bool> hasPermission();

  /// Asks for the runtime Bluetooth permission.
  Future<bool> requestPermission();

  /// True when the permission was refused with "don't ask again", which only
  /// the system Settings screen can undo.
  Future<bool> isPermissionPermanentlyDenied();

  /// Devices already paired with this handset. Pairing is a system flow; the
  /// app cannot silently bond a radio it has never been granted access to.
  Future<List<PrinterDevice>> pairedDevices();

  /// Starts the system pairing flow for [address].
  ///
  /// Returns whether the device is paired *when the call completes*; the system
  /// dialog is asynchronous and the user may dismiss it.
  Future<bool> pair(String address);

  Future<bool> isPaired(String address);

  /// Opens a link, reusing an already-open one.
  ///
  /// Lazy and cheap on purpose: it is called before every print, so a till that
  /// prints all day must not pay a discovery scan each time.
  Future<void> connect(String address, {Duration timeout});

  /// Writes raw ESC/POS bytes.
  Future<void> send(Uint8List bytes);

  /// True when the link is currently open.
  Future<bool> isConnected();

  Future<void> disconnect();

  /// Releases everything. Called when the app is disposed.
  Future<void> dispose();
}
