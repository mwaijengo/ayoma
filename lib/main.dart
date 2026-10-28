import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'screens/app_shell.dart';
import 'screens/splash_screen.dart';
import 'services/api.dart';
import 'services/push.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'widgets/app_restarter.dart';
import 'widgets/remote_control.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(AppTheme.overlayStyle);
  // Only the player may rotate to landscape.
  SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);

  var version = '1.0.0';
  try {
    version = (await PackageInfo.fromPlatform()).version;
  } catch (_) {
    // Keeps the default; only used for update checks.
  }
  final baseUrl = configuredApiUrl();
  final platform = kIsWeb ? 'web' : defaultTargetPlatform.name;
  final state = await AppState.load(
    appVersion: version,
    api: (prefs, deviceId) => AyomaApi(
      baseUrl: baseUrl,
      deviceId: deviceId,
      prefs: prefs,
      appVersion: version,
      platform: platform,
    ),
  );
  runApp(AyomaApp(state: state));

  state.sync(force: true);
  state.startAutoSync();
  PushService.start(state);
}

class AyomaApp extends StatelessWidget {
  const AyomaApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppTheme.overlayStyle,
        child: AppRestarter(
          child: MaterialApp(
            title: 'AyomaMax',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.dark(),
            home: ColoredBox(
              color: AppColors.backdrop,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: const RemoteControl(
                    child: SplashGate(child: AppShell()),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
