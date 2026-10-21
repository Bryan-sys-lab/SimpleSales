// What the server says the current release is.
//
// ## Why the comparison is by build number and not by name
//
// Android's own rule: an APK is accepted as an update only if its `versionCode`
// is HIGHER than the installed one. A higher `versionName` with a lower or equal
// `versionCode` is rejected by the OS before any of this code runs, with
// INSTALL_FAILED_VERSION_DOWNGRADE.
//
// So the manifest's `build` is the field that decides, and `versionName` is
// carried only so the app can label the prompt with something a shopkeeper
// recognises ("2.1.0" rather than "7"). Deriving the decision from the name
// instead — "is 2.1.0 newer than 2.0.0" — is a string comparison that is wrong
// for 2.10.0 against 2.9.0.
library;

import 'package:flutter/foundation.dart';

/// Why the app believes an update is available.
enum UpdateUrgency {
  /// Shown once, dismissible, and the shop carries on.
  normal,

  /// Shown on every launch and not dismissible while it is outstanding.
  required,
}

/// One release, as the server describes it.
@immutable
class AppRelease {
  const AppRelease({
    required this.build,
    required this.versionName,
    required this.downloadUrl,
    required this.notes,
    this.required = false,
    this.minimumBuild,
  });

  /// The Android `versionCode`. This is the field the comparison uses.
  final int build;

  /// The human-readable version. Display only.
  final String versionName;

  /// Where the APK is.
  final String downloadUrl;

  /// What changed, for the prompt.
  final String notes;

  /// Whether the shop must take it.
  final bool required;

  /// The oldest build this release can be installed OVER.
  ///
  /// Null means "any". A non-null value matters when a release changes the
  /// database in a way an older build cannot read: the server can say "you must
  /// be at build 12 or later", and a shop on build 9 is told to update first
  /// rather than being handed an APK that will not open its own data.
  final int? minimumBuild;

  /// Reads a release from the manifest the server serves.
  ///
  /// Returns null for anything malformed, rather than a half-built release with
  /// a zero build number that would read as "ancient" and silently suppress the
  /// update forever. A version endpoint that answers nonsense should be treated
  /// as an endpoint that did not answer.
  static AppRelease? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final build = raw['build'];
    final version = raw['version'];
    final url = raw['downloadUrl'];
    if (build is! int || build <= 0) return null;
    if (version is! String || version.trim().isEmpty) return null;
    if (url is! String || url.trim().isEmpty) return null;

    final notesRaw = raw['notes'];
    final minimumRaw = raw['minimumBuild'];

    return AppRelease(
      build: build,
      versionName: version.trim(),
      downloadUrl: url.trim(),
      notes: notesRaw is String ? notesRaw.trim() : '',
      required: raw['required'] == true,
      minimumBuild: minimumRaw is int ? minimumRaw : null,
    );
  }

  /// How urgently this should be presented.
  UpdateUrgency get urgency =>
      required ? UpdateUrgency.required : UpdateUrgency.normal;
}

/// What the update flow found when it looked.
sealed class UpdateCheck {
  const UpdateCheck();
}

/// Already on the newest build.
class UpdateUpToDate extends UpdateCheck {
  const UpdateUpToDate();
}

/// A newer build exists.
class UpdateAvailable extends UpdateCheck {
  const UpdateAvailable(this.release);

  final AppRelease release;
}

/// Why a check could not be completed.
enum UpdateCheckFailure {
  /// The server could not be reached at all.
  ///
  /// No answer, a timeout, a socket error: the till is offline or the server
  /// is down. Nothing about the release is known.
  unreachable,

  /// The server answered, but not with something that describes a release.
  ///
  /// A proxy's error page, a stale response, a manifest that does not parse.
  /// The server IS reachable; what it said is not usable.
  malformed,
}

/// The check could not be completed.
class UpdateCheckFailed extends UpdateCheck {
  const UpdateCheckFailed(this.failure, [this.detail]);

  /// What went wrong, in terms the screen can put in a sentence.
  ///
  /// A TYPE rather than a string, because a raw reason — "manifest 404",
  /// "manifest not JSON", a socket exception's own words — is a line of
  /// technical text handed to a shopkeeper, and nobody can act on it. The
  /// detail belongs in the log, where a developer can read it.
  final UpdateCheckFailure failure;

  /// The technical cause, for the log. Never shown to the owner.
  final String? detail;
}
