import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'app_brand.dart';
import 'l10n/generated/app_localizations.dart';
import 'models/crash_log.dart';
import 'routing/app_router.dart';
import 'routing/app_stage_controller.dart';
import 'services/app_state.dart';
import 'services/account_deletion_service.dart';
import 'services/backend_service.dart';
import 'services/app_update_service.dart';
import 'services/live_channel_service.dart';
import 'services/telemetry_service.dart';
import 'services/failure_recorder.dart';
import 'theme/app_theme.dart';
import 'services/app_release.dart';
import 'routing/routes.dart';

/// Sentry DSN for crash reporting - get from https://sentry.io
const String sentryDsn = String.fromEnvironment(
  'SENTRY_DSN',
  defaultValue: '', // Empty = crash reporting disabled
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The browser has no native sqflite plugin, so the default factory throws on
  // the first database access. Point it at the IndexedDB-backed wasm build;
  // native platforms keep their own factory.
  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
  }

  // The phone's own failure log. The framework hook is set HERE rather than
  // inside the recorder, so the whole error path is visible at the one place
  // that bootstraps the app: an `install()` that `main` then overwrote left the
  // recorder's copy unreachable.
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    if (sentryDsn.isNotEmpty) {
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

  // Initialize Sentry for crash reporting (if DSN provided). A malformed DSN
  // must never prevent the app from starting, so init is guarded and the app
  // always runs.
  if (sentryDsn.isNotEmpty) {
    try {
      await SentryFlutter.init(
        (SentryFlutterOptions options) {
          options.dsn = sentryDsn;
          options.tracesSampleRate = kReleaseMode ? 0.1 : 0.0;
          options.environment = kReleaseMode ? 'production' : 'development';
        },
        appRunner: () => runApp(const DukaPosApp()),
      );
      _sentryReady = true;
      return;
    } catch (error) {
      debugPrint('Crash reporting disabled (invalid SENTRY_DSN): $error');
    }
  }
  runApp(const DukaPosApp());
}

bool _sentryReady = false;

/// The composition root.
///
/// Everything the app needs is provided HERE and nowhere else: the session, the
/// boot gate, the router. A screen reaches downward for its dependencies and
/// never sideways for someone else's.
class DukaPosApp extends StatelessWidget {
  const DukaPosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<AppState>(create: (_) => AppState()),
        // The boot gate reads the session, so it is created after it — and both
        // live ABOVE `MaterialApp.router`, because the router's `redirect` reads
        // the gate and a provider below the router could not be seen by the
        // guard.
        ChangeNotifierProvider<AppStageController>(
          create: (BuildContext context) =>
              AppStageController(context.read<AppState>())..boot(),
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
      child: const _UpdateGate(child: _LiveChannelGate(child: _ThemedApp())),
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
        return child ?? const SizedBox.shrink();
      },
      routerConfig: context.read<GoRouter>(),
      theme: themes.light,
      darkTheme: themes.dark,
      // Both themes are hand-authored and both pass AA independently, so the
      // system setting is honoured rather than forced. The mode is read from
      // `MediaQuery.platformBrightnessOf` inside each theme's own construction,
      // which means the OS choice is respected with no stored preference and
      // therefore no first-frame flash: there is nothing to restore late.
      themeMode: ThemeMode.system,

      // Localization. Three things have to be wired together or "English-only"
      // silently costs more than it looks:
      //
      //   * `AppLocalizations.localizationsDelegates` already contains the three
      //     `Global*` delegates, so appending them again would duplicate each one
      //     and `Localizations._loadAll` would take the first — which is the
      //     wrong one the moment anyone vendors their own.
      //   * `supportedLocales` comes from the ARB catalogue rather than a
      //     hand-written list, so a locale cannot be half-shipped: adding
      //     `app_sw.arb` is the whole of adding Swahili.
      //   * `locale` is left null so the OS decides. There is nothing to restore
      //     before the first frame because there is no stored preference, which
      //     is why there is no locale flash on boot the way a persisted choice
      //     would cause.
      localizationsDelegates: AppLocalizations.localizationsDelegates,
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Read in the first frame, not in initState: the session completes its own
    // bootstrap before this widget is mounted, but reading a provider before
    // the first build is the kind of thing that works by accident.
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only `resumed` counts as foreground. `inactive` is a transient state an
    // Android device passes through for a call or the notification shade, and
    // closing the socket for it would drop the channel for no reason.
    final foreground = state == AppLifecycleState.resumed;
    context.read<LiveChannelService>().setForeground(foreground);
    if (foreground) unawaited(_sync());
  }

  /// Applies the current link state and asks for a snapshot.
  Future<void> _sync() async {
    if (!mounted) return;
    final channel = context.read<LiveChannelService>();
    final linked = await BackendService.isBackendLinked;
    channel.setLinked(linked);
    // One snapshot on entering the foreground, so a returning shop sees current
    // figures rather than whatever the last visit left on screen.
    if (linked) channel.requestRead();
  }

  @override
  Widget build(BuildContext context) {
    // Signing in, signing out, or unlinking is exactly when the channel's
    // premise changes, and a socket pointed at the previous shop is worse than
    // no socket. The session's own notifyListeners triggers this rebuild.
    context.watch<LiveChannelService>();
    unawaited(_sync());
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

class _UpdateGateState extends State<_UpdateGate>
    with WidgetsBindingObserver {
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
