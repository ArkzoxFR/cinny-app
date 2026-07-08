import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'update_service.dart';

/// Icône dans la barre des tâches Windows : clic sur la croix de la fenêtre
/// = masquer au lieu de quitter, clic-droit sur l'icône = menu avec
/// "Ouvrir", l'état de la mise à jour en cours, et "Quitter" (le seul moyen
/// de vraiment fermer l'app).
class TrayService with TrayListener, WindowListener {
  TrayService._();
  static final TrayService instance = TrayService._();

  bool _initialized = false;
  Timer? _updateCheckTimer;

  Future<void> init() async {
    if (!Platform.isWindows || _initialized) return;
    _initialized = true;

    // L'intégration barre des tâches est une amélioration, pas le cœur de
    // l'app : si quoi que ce soit échoue ici (config système inhabituelle...),
    // la webview Cinny doit quand même démarrer normalement.
    try {
      await windowManager.ensureInitialized();
      await windowManager.setPreventClose(true);
      windowManager.addListener(this);

      await localNotifier.setup(appName: 'Cinny', shortcutPolicy: ShortcutPolicy.requireCreate);

      await trayManager.setIcon(_resolveAssetPath('assets/tray_icon.ico'));
      await trayManager.setToolTip('Cinny');
      trayManager.addListener(this);

      UpdateService.instance.status.addListener(_onUpdateStatusChanged);
      await _rebuildMenu();

      _updateCheckTimer = Timer.periodic(
        const Duration(minutes: 10),
        (_) => UpdateService.instance.checkForUpdate(),
      );
      Future.delayed(const Duration(seconds: 5), () => UpdateService.instance.checkForUpdate());
    } catch (e) {
      debugPrint('TrayService.init a échoué, poursuite sans icône barre des tâches : $e');
    }
  }

  void dispose() {
    _updateCheckTimer?.cancel();
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    UpdateService.instance.status.removeListener(_onUpdateStatusChanged);
  }

  /// Les assets Flutter ne sont pas accessibles par chemin disque au sens où
  /// tray_manager en a besoin : ils sont copiés tels quels par le build dans
  /// data/flutter_assets/, à côté de l'exécutable.
  String _resolveAssetPath(String relativeAssetPath) {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    return '$exeDir${Platform.pathSeparator}data${Platform.pathSeparator}flutter_assets${Platform.pathSeparator}$relativeAssetPath';
  }

  Menu _buildMenu(UpdateStatus status) {
    final items = <MenuItem>[
      MenuItem(key: 'open', label: 'Ouvrir Cinny'),
      MenuItem.separator(),
    ];

    switch (status.phase) {
      case UpdatePhase.available:
        items.add(MenuItem(
          key: 'install_update',
          label: 'Installer la mise à jour (v${status.latestVersion})',
        ));
        break;
      case UpdatePhase.downloading:
        final pct = (status.progress * 100).clamp(0, 100).toStringAsFixed(0);
        items.add(MenuItem(key: 'downloading', label: 'Téléchargement… $pct %', disabled: true));
        break;
      case UpdatePhase.readyToRestart:
        items.add(MenuItem(key: 'restart', label: 'Redémarrer'));
        break;
      case UpdatePhase.error:
      case UpdatePhase.idle:
        break;
    }

    items.add(MenuItem.separator());
    items.add(MenuItem(key: 'quit', label: 'Quitter'));
    return Menu(items: items);
  }

  Future<void> _rebuildMenu() async {
    await trayManager.setContextMenu(_buildMenu(UpdateService.instance.status.value));
  }

  void _onUpdateStatusChanged() {
    _rebuildMenu();
    final s = UpdateService.instance.status.value;
    if (s.phase == UpdatePhase.available) {
      _notify(
        'Mise à jour disponible',
        'La version ${s.latestVersion} de Cinny est prête à être installée.',
      );
    } else if (s.phase == UpdatePhase.readyToRestart) {
      _notify(
        'Redémarrage nécessaire',
        'Clic droit sur l\'icône Cinny puis « Redémarrer » pour terminer la mise à jour.',
      );
    } else if (s.phase == UpdatePhase.error) {
      _notify('Mise à jour impossible', s.error ?? 'Une erreur est survenue.');
    }
  }

  void _notify(String title, String body) {
    LocalNotification(title: title, body: body).show();
  }

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() {
    // Sur Windows, contrairement à macOS, le menu ne s'affiche pas tout seul
    // au clic droit : il faut explicitement le déclencher ici.
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'open':
        await windowManager.show();
        await windowManager.focus();
        break;
      case 'install_update':
        await windowManager.show();
        await windowManager.focus();
        await UpdateService.instance.downloadUpdate();
        break;
      case 'restart':
        await UpdateService.instance.restartAndInstall();
        break;
      case 'quit':
        await trayManager.destroy();
        exit(0);
    }
  }

  @override
  void onWindowClose() async {
    if (await windowManager.isPreventClose()) {
      await windowManager.hide();
    }
  }
}
