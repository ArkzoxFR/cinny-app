import 'package:flutter/material.dart';
import 'services/config_service.dart';
import 'services/remote_config_service.dart';
import 'services/tray_service.dart';
import 'screens/setup_screen.dart';
import 'screens/webview_screen.dart';
import 'widgets/update_overlay.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // No-op sur Android/iOS : TrayService ne s'active que sur Windows.
  await TrayService.instance.init();
  runApp(const CinnyApp());
}

class CinnyApp extends StatelessWidget {
  const CinnyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cinny',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF3E7BFA),
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF3E7BFA),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      builder: (context, child) {
        return Stack(
          children: [
            if (child != null) child,
            const UpdateOverlay(),
          ],
        );
      },
      home: const _StartupGate(),
    );
  }
}

/// Écran invisible qui décide, au tout premier lancement (ou à chaque
/// démarrage), où envoyer l'utilisateur :
///  - vers l'écran "webview" si une URL est déjà connue (locale ou forcée
///    à distance par l'admin),
///  - vers l'écran de configuration initiale sinon.
class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  @override
  void initState() {
    super.initState();
    _resolveStartup();
  }

  Future<void> _resolveStartup() async {
    // 1) On regarde d'abord ce qui est déjà sauvegardé sur l'appareil.
    final localUrl = await ConfigService.getSavedUrl();

    // 2) On interroge la config distante (best-effort, avec timeout court :
    // si ça échoue, l'app continue avec ce qu'elle a en local).
    final remote = await RemoteConfigService.fetch();

    if (!mounted) return;

    // Cas 1 : l'admin a défini un "force_url" -> il a la priorité absolue,
    // même si l'utilisateur avait déjà configuré autre chose. C'est le
    // levier de secours en cas de problème serveur.
    if (remote != null && remote.hasForceUrl) {
      await ConfigService.saveAdminForcedUrl(remote.forceUrl!);
      _goToWebview(
        remote.forceUrl!,
        message: remote.message ?? 'Serveur mis à jour à distance par l\'administrateur.',
      );
      return;
    }

    // Cas 2 : l'utilisateur a déjà configuré son propre serveur -> on l'utilise.
    if (localUrl != null && localUrl.isNotEmpty) {
      _goToWebview(localUrl, message: remote?.message);
      return;
    }

    // Cas 3 : premier lancement, rien de sauvegardé -> écran de configuration,
    // pré-rempli avec le "default_url" distant si disponible.
    _goToSetup(prefill: remote?.defaultUrl, message: remote?.message);
  }

  void _goToWebview(String url, {String? message}) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => WebviewScreen(url: url, maintenanceMessage: message),
      ),
    );
  }

  void _goToSetup({String? prefill, String? message}) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SetupScreen(prefillUrl: prefill, infoMessage: message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
