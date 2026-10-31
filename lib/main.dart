import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/app_state.dart';
import 'core/config.dart';
import 'core/settings.dart';
import 'core/theme.dart';
import 'screens/auth_screen.dart';
import 'screens/reset_password_screen.dart';
import 'screens/shell.dart';
import 'screens/skeleton_screen.dart';
import 'screens/splash_screen.dart';
import 'services/rag_service.dart';
import 'services/inbox.dart';

/// Set when the user opens a password-reset link from their email. AuthGate
/// then shows the "new password" screen.
final recoveryPending = ValueNotifier<bool>(false);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Settings.instance.load();
  
  if (AppConfig.supabaseUrl.isEmpty || AppConfig.supabaseAnonKey.isEmpty) {
    runApp(const _SetupError());
    return;
  }
  await Supabase.initialize(url: AppConfig.supabaseUrl, anonKey: AppConfig.supabaseAnonKey);
  // Listen from the start, because the reset link can arrive while the splash video is playing.
  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    if (data.event == AuthChangeEvent.passwordRecovery) recoveryPending.value = true;
  });
  Inbox.instance.init();
  await RagService.instance.load();
  runApp(const CoopIQApp());
}

class CoopIQApp extends StatelessWidget {
  const CoopIQApp({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Settings.instance,
        builder: (context, _) => SettingsScope(
          settings: Settings.instance,
          child: MaterialApp(
            title: 'CoopIQ',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(),
            darkTheme: buildDarkTheme(),
            themeMode: Settings.instance.themeMode,
            home: const SplashVideoScreen(next: AuthGate()),
          ),
        ),
      );
}

/// Shows the login screen until there is a session, then loads the user's data.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final StreamSubscription<AuthState> _sub;
  Session? _session = Supabase.instance.client.auth.currentSession;
  bool _ready = false;
  String? _loadedFor;

  @override
  void initState() {
    super.initState();
    recoveryPending.addListener(_maybeShowRecovery);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowRecovery());
    _sync(_session);
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
      setState(() => _session = data.session);
      _sync(data.session);
    });
  }

  void _maybeShowRecovery() {
    if (!recoveryPending.value || !mounted) return;
    recoveryPending.value = false;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ResetPasswordScreen()));
  }

  Future<void> _sync(Session? s) async {
    if (s == null) {
      AppState.instance.reset();
      _loadedFor = null;
      if (mounted) setState(() => _ready = false);
      return;
    }
    if (_loadedFor == s.user.id) return;
    _loadedFor = s.user.id;
    if (mounted) setState(() => _ready = false);
    await AppState.instance.load();
    if (mounted) setState(() => _ready = true);
  }

  @override
  void dispose() {
    recoveryPending.removeListener(_maybeShowRecovery);
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Shimmering placeholder while the user's data loads, then a short fade into the app.
    final Widget page;
    if (_session == null) {
      page = const AuthScreen(key: ValueKey('auth'));
    } else if (!_ready) {
      page = const HomeSkeleton(key: ValueKey('skeleton'));
    } else {
      page = const Shell(key: ValueKey('shell'));
    }
    return AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: page);
  }
}

class _SetupError extends StatelessWidget {
  const _SetupError();
  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(28),
            child: Center(
              child: Text(
                'Supabase is not configured.\n\nRun with:\nflutter run --dart-define-from-file=env.json\n\nSee env.example.json for the keys.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
}
