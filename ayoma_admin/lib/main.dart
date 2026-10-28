import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'state/session.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(AdminApp(session: Session(prefs: prefs)));
}

class AdminApp extends StatefulWidget {
  const AdminApp({super.key, required this.session});

  final Session session;

  @override
  State<AdminApp> createState() => _AdminAppState();
}

class _AdminAppState extends State<AdminApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) widget.session.checkExpiry();
  }

  @override
  Widget build(BuildContext context) {
    return SessionScope(
      session: widget.session,
      child: AnnotatedRegion(
        value: AppTheme.overlayStyle,
        child: MaterialApp(
          title: 'AyomaMax Admin',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark(),
          home: const _Gate(),
        ),
      ),
    );
  }
}

class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: session.loggedIn
          ? const HomeShell(key: ValueKey('home'))
          : const LoginScreen(key: ValueKey('login')),
    );
  }
}
