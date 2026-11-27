import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'app_brand.dart';
import 'l10n/app_localizations_config.dart';
import 'l10n/generated/app_localizations.dart';
import 'models/crash_log.dart';
import 'routing/app_router.dart';
import 'routing/app_stage_controller.dart';
import 'services/app_state.dart';
import 'services/account_deletion_service.dart';
import 'services/backend_service.dart';
import 'services/build_configuration.dart';
import 'services/app_update_service.dart';
import 'services/live_channel_service.dart';
import 'services/telemetry_service.dart';
import 'services/failure_recorder.dart';
import 'theme/app_theme.dart';
import 'theme/appearance_controller.dart';
import 'services/app_release.dart';
import 'routing/routes.dart';
import 'services/diagnostics_upload_service.dart';
import 'services/identity_service.dart';
import 'services/workspace_service.dart';
import 'theme/app_colors.dart';
import 'ui/components/shop_screen_background.dart';

/// Sentry DSN for crash reporting - get from https://sentry.io
const String sentryDsn = String.fromEnvironment(
  'SENTRY_DSN',
  defaultValue: '', // Empty = crash reporting disabled
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final appearance = AppearanceController();

  // The build's own configuration, checked before anything else runs.
  //
  // A release build that was never given a real backend URL points every
  // shop's till at a server on the builder's own machine. The check still
  // runs — but it no longer STOPS the app.
  //
  // It used to: the build refused to open and showed a dead-end screen. The
  // reasoning was sound (a till that cannot reach a server cannot issue a
  // KRA receipt) and the consequence was not: the build could not be shown to
  // anyone, so the person shipping it never saw the app, and the shop could
  // not try it before the backend work landed.
  //
  // The till is offline-first. A build with no server is a LOCAL-ONLY build,
  // and that is a perfectly good thing to be able to run and hand to a shop
  // while the APIs are still in flight. So the app starts, the till sells,
  // and Diagnostics says which parts will not work until the addresses are
  // supplied.
  final String? configurationProblem = BuildConfiguration.problem;
  if (configurationProblem != null) {
    // Recorded, so the phone's own log knows the build was incomplete — but
    // NOT as a failure: nothing failed. The build is a local-only build.
    failureRecorder.record(
      kind: CrashKind.warning,
      message: configurationProblem,
    );
  }

  // The phone's own failure log. The framework hook is set HERE rather than
  // inside the recorder, so the whole error path is visible at the one place
  // that bootstraps the app: an `install()` that `main` then overwrote left the
  // recorder's copy unreachable.
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    if (sentryDsn.isNotEmpty && _sentryReady) {
      Sentry.captureException(details.exception, stackTrace: details.stack);
    }
    // And the phone's own log. Independent of Sentry, deliberately: an empty
    // DSN must not mean "record nothing", because the empty-DSN case is exactly
    // the one where a shop has no other way to say what broke.
    failureRecorder.record(
      kind: details.exception is Error ? CrashKind.crash : CrashKind.error,
      message: details.exceptionAsString(),
      stack: details.stack?.toString(),
    );
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    if (sentryDsn.isNotEmpty && _sentryReady) {
      Sentry.captureException(error, stackTrace: stack);
    }
    // Whatever Sentry does with it, this side records it. The app's own log is
    // the one that works with no DSN, no network and no third party.
    failureRecorder.record(
      kind: CrashKind.crash,
      message: error.toString(),
      stack: stack.toString(),
    );
    // Without a working crash reporter, returning true would mark the error as
    // handled and discard it silently. Log it so it is visible either way.
    debugPrint('Unhandled error: $error\n$stack');
    return false;
  };

  runApp(DukaPosApp(appearance: appearance));
  unawaited(_loadAppearancePreference(appearance));
  unawaited(_captureFailureEnvironment());
  if (sentryDsn.isNotEmpty) unawaited(_initializeSentry());
}

bool _sentryReady = false;

Future<void> _loadAppearancePreference(
  AppearanceController appearance,
) async {
  try {
    await appearance.loadPreference();
  } catch (error, stack) {
    debugPrint('Appearance preference unavailable: $error\n$stack');
    failureRecorder.remember(
      kind: CrashKind.warning,
      message: 'Appearance preference could not be loaded: $error',
      stack: stack.toString(),
      operation: 'loading appearance preference',
    );
  }
}

Future<void> _captureFailureEnvironment() async {
  try {
    await failureRecorder.captureEnvironment();
  } catch (error, stack) {
    debugPrint('Device diagnostics unavailable: $error\n$stack');
  }
}

Future<void> _initializeSentry() async {
  try {
    await SentryFlutter.init((SentryFlutterOptions options) {
      options.dsn = sentryDsn;
      options.tracesSampleRate = kReleaseMode ? 0.1 : 0.0;
      options.environment = kReleaseMode ? 'production' : 'development';
    });
    _sentryReady = true;
  } catch (error) {
    debugPrint('Crash reporting disabled (invalid SENTRY_DSN): $error');
  }
}

/// The composition root.
///
/// Everything the app needs is provided HERE and nowhere else: the session, the
/// boot gate, the router, and the appearance preference. A screen reaches
/// downward for its dependencies and never sideways for someone else's.
class DukaPosApp extends StatelessWidget {
  const DukaPosApp({
    required this.appearance,
    this.bootOnStart = true,
    super.key,
  });

  /// The persisted appearance preference (system / light / dark).
  final AppearanceController appearance;

  /// Allows widget tests to inspect the synchronous app shell without starting
  /// local database I/O under the test binding's fake clock.
  final bool bootOnStart;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppearanceController>.value(
      value: appearance,
      child: MultiProvider(
        providers: <SingleChildWidget>[
          ChangeNotifierProvider<AppState>(create: (_) => AppState()),
          // The boot gate reads the session, so it is created after it — and both
          // live ABOVE `MaterialApp.router`, because the router's `redirect` reads
          // the gate and a provider below the router could not be seen by the
          // guard.
          ChangeNotifierProvider<AppStageController>(
            create: (BuildContext context) {
              final AppStageController controller =
                  AppStageController(context.read<AppState>());
              if (bootOnStart) unawaited(controller.boot());
              return controller;
            },
          ),
          // The live change stream. Created after the session and before the
          // router so a screen can watch it from any branch, and torn down with
          // the tree so a socket is never left open behind a closed app.
          ChangeNotifierProvider<LiveChannelService>(
            create: (BuildContext context) => LiveChannelService()..start(),
          ),
          // The update channel. Provided here so one instance serves the whole
          // app: a check started from the splash banner is the same download the
          // Settings row installs, rather than two of each.
          ChangeNotifierProvider<AppUpdateService>(
            create: (BuildContext context) => AppUpdateService(),
          ),
          // Last: the router needs the two above. It is never rebuilt afterwards —
          // `refreshListenable` re-runs the guard on its own, and rebuilding a
          // `GoRouter` throws away every branch's navigation stack.
          Provider<GoRouter>(
              create: (BuildContext context) => appRouter(context)),
        ],
        // The gate sits above the router so a lifecycle change reaches the
        // channel from one place, whatever branch is showing.
        child: const _DiagnosticsSyncGate(
          child: _UpdateGate(child: _LiveChannelGate(child: _ThemedApp())),
        ),
      ),
    );
  }
}

/// Reads the two providers the router is built from.
///
/// Named so the dependency arrow is stated once: `lib/routing` depends on the
/// session and the boot gate, and on nothing above them.
GoRouter appRouter(BuildContext context) => buildAppRouter(
      stage: context.read<AppStageController>(),
      appState: context.read<AppState>(),
    );

/// The app widget: theme, locale and the router, injected exactly once.
class _ThemedApp extends StatelessWidget {
  const _ThemedApp();

  @override
  Widget build(BuildContext context) {
    final appearance = AppearanceController.of(context);
    final ({ThemeData light, ThemeData dark}) themes = buildDukaThemes();

    return MaterialApp.router(
      title: SimplePosBrand.appName,
      debugShowCheckedModeBanner: false,
      // Where the "press back again to exit" sentence is installed.
      //
      // The handler itself lives with the router, because the guard that calls it
      // is built by each route's page. What the app owns is the sentence, and the
      // sentence needs this device's locale and a `ScaffoldMessenger` — both of
      // which live BELOW the `MaterialApp`. An `AppLocalizations.of` up here is
      // above them and finds nothing, which is why this is a `builder` and not a
      // field assignment: `MaterialApp.builder` is final, and a PopScope above
      // the router was proved inert anyway.
      builder: (BuildContext inner, Widget? child) {
        final AppLocalizations l10n = AppLocalizations.of(inner);
        final Brightness brightness = switch (appearance.themeMode) {
          ThemeMode.dark => Brightness.dark,
          ThemeMode.light => Brightness.light,
          ThemeMode.system => MediaQuery.platformBrightnessOf(inner),
        };
        final AppColors colors = appearance.colorsFor(
          brightness: brightness,
          highContrast: MediaQuery.highContrastOf(inner),
        );
        setSystemBackHint(() {
          final ScaffoldMessengerState? messenger =
              ScaffoldMessenger.maybeOf(inner);
          if (messenger == null) return;
          messenger
            ..clearSnackBars()
            ..showSnackBar(SnackBar(
              content: Text(l10n.actionPressBackAgainToExit),
              duration: const Duration(seconds: 2),
            ));
        });
        return Consumer<AppState>(
          builder: (BuildContext context, AppState state, _) =>
              ShopScreenBackground(
            brightness: brightness,
            colors: colors,
            isShopScreen: true,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      routerConfig: context.read<GoRouter>(),
      theme: themes.light,
      darkTheme: themes.dark,
      // The appearance preference overrides the OS when the user has chosen
      // Light or Dark; System follows the platform. The preference is loaded
      // before the first frame (see main), so there is no flash of the wrong
      // brightness. High contrast is applied on top by screens that read
      // `AppColors.colorsFor()` with `MediaQuery.highContrastOf(context)`.
      themeMode: appearance.themeMode,

      // Use delegates matching the Material and Cupertino packages in use.
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: null,
      // No `localeResolutionCallback`: the default resolution picks the first
      // supported locale whose language matches the device and falls back to the
      // first supported locale, so an OS set to French still gets English rather
      // than English copy inside French chrome. Adding a callback would only be
      // needed once the app has a language the OS cannot select.
      // A theme change is a sudden luminance change the user did not cause.
      // Interpolating it renders a half-styled state no screen was laid out for.
      themeAnimationStyle: AnimationStyle.noAnimation,
    );
  }
}

/// Retries a locally recorded crash report after startup/recovery.
///
/// A process can be killed before the recorder's debounce timer fires. The
/// local crash row is the durable queue; once the app has a signed-in tenant,
/// this gate uploads it and stops. It never blocks the UI or a sale.
class _DiagnosticsSyncGate extends StatefulWidget {
  const _DiagnosticsSyncGate({required this.child});
  final Widget child;

  @override
  State<_DiagnosticsSyncGate> createState() => _DiagnosticsSyncGateState();
}

class _DiagnosticsSyncGateState extends State<_DiagnosticsSyncGate>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _syncing = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _attemptUpload());
    _timer =
        Timer.periodic(const Duration(seconds: 30), (_) => _attemptUpload());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _attemptUpload();
  }

  void _attemptUpload() {
    if (_finished || _syncing || !BuildConfiguration.isConnected) return;
    _syncing = true;
    unawaited(() async {
      try {
        if (await IdentityService.accessToken == null ||
            await WorkspaceService.activeTenantId() == null) {
          return;
        }
        final result = await DiagnosticsUploadService.instance.uploadAndClear();
        if (result.ok) {
          _finished = true;
          _timer?.cancel();
          _timer = null;
        }
      } catch (_) {
        // Reporting stays best-effort; retry when the app resumes or later.
      } finally {
        _syncing = false;
      }
    }());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Keeps the live channel honest about the app's actual state.
///
/// Two facts drive the channel and neither lives in it: whether this shop is
/// linked to a backend at all, and whether the app is in the foreground. Both
/// are read here, where the providers and the lifecycle both exist, rather than
/// being duplicated inside the channel or guessed at by a screen.
///
/// A backgrounded app closes the socket rather than leaving it open: Android
/// can kill the process at any point, and a shop on a counter needs no live
/// refresh while the screen is off. Returning to the foreground reconnects.
class _LiveChannelGate extends StatefulWidget {
  const _LiveChannelGate({required this.child});

  final Widget child;

  @override
  State<_LiveChannelGate> createState() => _LiveChannelGateState();
}

class _LiveChannelGateState extends State<_LiveChannelGate>
    with WidgetsBindingObserver {
  late LiveChannelService _channel;
  late AppState _appState;
  int _lastSeenGeneration = -1;
  bool _lastIdentityVerified = false;

  /// Generation counter for snapshot requests. Incremented on every explicit
  /// transition that warrants a fresh snapshot (init, foreground resume, link
  /// change). `_sync()` only requests a snapshot when the generation has
  /// advanced past the last one served, so rebuilds and pong frames can never
  /// re-trigger a read.
  int _snapshotGeneration = 0;
  int _lastRequestedGeneration = -1;
  @override
  void initState() {
    super.initState();
    _channel = context.read<LiveChannelService>();
    _channel.addListener(_onLiveMessage);
    _appState = context.read<AppState>();
    _lastSeenGeneration = _appState.sessionGeneration;
    _lastIdentityVerified = _appState.identityVerified;
    _appState.addListener(_onSessionChanged);
    WidgetsBinding.instance.addObserver(this);
    // Read in the first frame, not in initState: the session completes its own
    // bootstrap before this widget is mounted, but reading a provider before
    // the first build is the kind of thing that works by accident.
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    _channel.removeListener(_onLiveMessage);
    _appState.removeListener(_onSessionChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Re-syncs the channel whenever the session changes (sign-in, sign-out,
  /// workspace switch). Without this the channel stays `off` after login
  /// until the next foreground resume.
  void _onSessionChanged() {
    final gen = _appState.sessionGeneration;
    final verified = _appState.identityVerified;
    final sessionChanged = gen != _lastSeenGeneration;
    final identityChanged = verified != _lastIdentityVerified;
    if (!sessionChanged && !identityChanged) return;
    if (sessionChanged) {
      _lastSeenGeneration = gen;
      _snapshotGeneration++;
    }
    if (identityChanged) {
      _lastIdentityVerified = verified;
      _snapshotGeneration++;
    }
    unawaited(_sync());
  }

  void _onLiveMessage() {
    final announcement = _channel.takePlatformAnnouncement();
    if (announcement == null || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: Text(announcement.title),
          content: Text(announcement.body),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(AppLocalizations.of(dialogContext).actionClose),
            ),
          ],
        ),
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only `resumed` counts as foreground. `inactive` is a transient state an
    // Android device passes through for a call or the notification shade, and
    // closing the socket for it would drop the channel for no reason.
    final foreground = state == AppLifecycleState.resumed;
    context.read<LiveChannelService>().setForeground(foreground);
    if (foreground) {
      // A foreground transition is an explicit sync trigger: advance the
      // generation so exactly one snapshot is requested.
      _snapshotGeneration++;
      unawaited(_sync());
    }
  }

  /// Applies the current link state and asks for a snapshot.
  ///
  /// Called once on initialization and once on each foreground transition.
  /// Never called from `build()`: a rebuild must not trigger a network read.
  Future<void> _sync() async {
    if (!mounted) return;
    final channel = context.read<LiveChannelService>();
    final linked = await BackendService.isBackendLinked;
    if (!mounted) return;
    channel.setLinked(linked);
    // Single-flight: request at most one snapshot per generation. Rebuilds,
    // pong frames and change notifications that fire while a read is pending
    // see the same generation and skip the request.
    if (linked && _snapshotGeneration > _lastRequestedGeneration) {
      _lastRequestedGeneration = _snapshotGeneration;
      channel.requestRead();
    }
  }

  @override
  Widget build(BuildContext context) {
    // build() is pure: no watch, no Future, no network request, no state
    // mutation. The gate does not rebuild on live messages; screens watch the
    // channel themselves and re-read when a change signal arrives.
    return widget.child;
  }
}

/// Checks for an update once per launch, and offers it.
///
/// Once per LAUNCH and not once per frame, because the check is a network call
/// on a till whose owner may open the app a hundred times a day. A shop that has
/// dismissed the prompt still gets it again next launch — which is right: an
/// update they said "later" to is not an update they refused.
class _UpdateGate extends StatefulWidget {
  const _UpdateGate({required this.child});

  final Widget child;

  @override
  State<_UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<_UpdateGate> with WidgetsBindingObserver {
  String? _shownAnnouncementId;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Record the session start. Telemetry is lazy: the first touch boots it.
    telemetry.recordAppOpen();
    // Retry any pending remote account deletion so the server-side account is
    // eventually removed even if the first attempt failed — Play Store
    // data-deletion compliance requires it. Safe to call when nothing is
    // pending; it returns false immediately in that case.
    unawaited(AccountDeletionService.retryPendingDeletion());
    // After the first frame, so the check runs against a mounted tree and any
    // prompt it raises has a navigator to sit above.
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        telemetry.recordAppOpen();
        // A platform announcement and a required release are both delivered
        // through the public manifest. Re-checking on resume makes an online
        // till receive a super-admin message without requiring a restart.
        unawaited(_check());
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        telemetry.recordAppClose();
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  Future<void> _check() async {
    if (!mounted) return;
    final service = context.read<AppUpdateService>();
    final result = await service.checkForUpdate();
    if (!mounted) return;

    final announcement = service.announcement;
    if (announcement != null && announcement.id != _shownAnnouncementId) {
      _shownAnnouncementId = announcement.id;
      await showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: Text(announcement.title),
          content: Text(announcement.body),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(AppLocalizations.of(dialogContext).actionClose),
            ),
          ],
        ),
      );
    }

    if (!mounted || result is! UpdateAvailable) return;

    final release = result.release;
    if (!release.required) return;
    // A required update is offered rather than installed: Android will not
    // permit a silent install, and pretending otherwise would be a button that
    // does nothing.
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(AppLocalizations.of(dialogContext).settingsUpdatesInstall),
        content: Text(
          AppLocalizations.of(dialogContext)
              .settingsUpdatesPromptBody(release.versionName),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(AppLocalizations.of(dialogContext).actionCancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              // Takes the owner to where the install actually happens, rather
              // than trying to drive it from here: Settings holds the progress
              // bar and the permission prompt.
              context.push(Routes.settings);
            },
            child:
                Text(AppLocalizations.of(dialogContext).settingsUpdatesRestart),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
