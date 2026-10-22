import 'package:flutter/foundation.dart';

import 'backend_service.dart';
import 'oidc_service.dart';

/// What this build was compiled with, and what it is therefore missing.
///
/// ## WHY THIS EXISTS
///
/// A release build used to REFUSE TO START when it had no server address or
/// no sign-in issuer. The reasoning was sound — a till that cannot reach a
/// server cannot issue a KRA receipt for the money it has taken — but the
/// consequence was not: the build could not be shown to anyone, so the person
/// building it had no way to see the app they were shipping, and the shop had
/// no way to try it before the APIs existed.
///
/// The till is offline-first. Everything that makes money move — the sale,
/// the stock, the reports, the receipt — happens on the phone. A build with
/// no server is a LOCAL-ONLY build, and a local-only build is a perfectly
/// good thing to be able to run, look at and hand to a shop while the
/// backend work is still in flight.
///
/// So the check survives, but it is no longer a gate. It is a NOTICE: the app
/// starts, the till sells, and the one screen that talks about the build says
/// which parts will not work until the addresses are supplied.
///
/// ## THE RULE LIVES WITH THE SERVICES
///
/// The two rules — "the backend URL is missing" and "the issuer is missing" —
/// belong to the two services that own those constants. This class only
/// ASKS, and carries the answer to the screens that have to say something
/// about it. It is a pure function of compile-time constants, so it can be
/// asked at any time and the answer never changes.
class BuildConfiguration {
  const BuildConfiguration._();

  /// Why this build may not be able to reach a server, or null when it can.
  ///
  /// Null in a debug build: localhost is exactly where the development server
  /// lives, so a debug build is never "unconfigured".
  static String? get problem {
    final String? backend = BackendService.releaseConfigurationProblem(
      url: BackendService.backendUrl,
      isRelease: kReleaseMode,
    );
    if (backend != null) return backend;
    return OidcService.releaseConfigurationProblem(
      issuer: OidcService.issuerForChecks,
      clientId: OidcService.clientIdForChecks,
      isRelease: kReleaseMode,
    );
  }

  /// Whether this build is missing something it would need.
  ///
  /// True means: the till runs, sells and reports, and the server-backed
  /// features — KRA receipts, M-Pesa, sync, cloud sign-in — do not.
  static bool get isIncomplete => problem != null;
}
