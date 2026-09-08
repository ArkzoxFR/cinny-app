import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:windows_taskbar/windows_taskbar.dart';

import 'unread_service.dart';
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

  Timer? _blinkTimer;
  bool _blinkVisible = true;
  StreamSubscription<CinnyNotification>? _notificationSub;

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

      await _refreshTrayIcon();
      PlatformDispatcher.instance.onPlatformBrightnessChanged = _refreshTrayIcon;
      await trayManager.setToolTip('Cinny');
      trayManager.addListener(this);

      UpdateService.instance.status.addListener(_onUpdateStatusChanged);
      UnreadService.instance.status.addListener(_onUnreadChanged);
      _notificationSub = UnreadService.instance.notifications.listen(_onCinnyNotification);
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
    _blinkTimer?.cancel();
    _notificationSub?.cancel();
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    UpdateService.instance.status.removeListener(_onUpdateStatusChanged);
    UnreadService.instance.status.removeListener(_onUnreadChanged);
    PlatformDispatcher.instance.onPlatformBrightnessChanged = null;
  }

  static String _badgeSlug(String label) => label == '9+' ? '9plus' : label;

  /// Icône du tray : suit le thème système (une icône fixe deviendrait
  /// invisible sur l'une des deux barres des tâches).
  ///
  /// La pastille n'y apparaît que si la fenêtre est masquée : quand elle est
  /// ouverte, c'est le bouton de la barre des tâches qui porte le badge (façon
  /// Teams), et doubler l'information serait redondant. Fenêtre masquée, en
  /// revanche, il n'y a plus de bouton du tout — le tray est alors le seul
  /// endroit possible.
  Future<void> _refreshTrayIcon() async {
    final isDark = PlatformDispatcher.instance.platformBrightness == Brightness.dark;
    final theme = isDark ? 'light' : 'dark';

    final badge = UnreadService.instance.status.value.badgeLabel;
    final showBadgeInTray = badge != null && _blinkVisible && !await _windowIsVisible();
    final suffix = showBadgeInTray ? '_${_badgeSlug(badge)}' : '';

    await trayManager.setIcon(_resolveAssetPath('assets/tray_icon_$theme$suffix.ico'));
  }

  Future<bool> _windowIsVisible() async {
    try {
      return await windowManager.isVisible();
    } catch (_) {
      return true;
    }
  }

  /// Badge numéroté sur le bouton de la barre des tâches + clignotement du
  /// bouton jusqu'à ce que la fenêtre revienne au premier plan, comme Teams.
  Future<void> _refreshTaskbar() async {
    final badge = UnreadService.instance.status.value.badgeLabel;
    try {
      if (badge == null) {
        await WindowsTaskbar.resetOverlayIcon();
        WindowsTaskbar.resetFlashTaskbarAppIcon();
        return;
      }
      final n = UnreadService.instance.status.value.count;
      final plural = n > 1 ? 's' : '';
      await WindowsTaskbar.setOverlayIcon(
        ThumbnailToolbarAssetIcon('assets/badge_${_badgeSlug(badge)}.ico'),
        tooltip: n > 0 ? '$n message$plural non lu$plural' : 'Nouveaux messages',
      );
    } catch (e) {
      debugPrint('Badge barre des tâches indisponible : $e');
    }
  }

  /// Clignotement du tray, utilisé seulement quand la fenêtre est masquée
  /// (sinon c'est le bouton de la barre des tâches qui clignote). Salves de
  /// ~8 s : un clignotement sans fin deviendrait vite pénible.
  void _startBlinkBurst() {
    _blinkTimer?.cancel();
    var toggles = 0;
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 600), (timer) {
      toggles++;
      _blinkVisible = !_blinkVisible;
      _refreshTrayIcon();
      if (toggles >= 14) {
        timer.cancel();
        _blinkVisible = true;
        _refreshTrayIcon();
      }
    });
  }

  void _onUnreadChanged() {
    final status = UnreadService.instance.status.value;
    if (!status.hasUnread) {
      _blinkTimer?.cancel();
      _blinkVisible = true;
      trayManager.setToolTip('Cinny');
    } else {
      final n = status.count;
      final plural = n > 1 ? 's' : '';
      trayManager.setToolTip(
        n > 0 ? 'Cinny — $n message$plural non lu$plural' : 'Cinny — nouveaux messages',
      );
    }
    _refreshTrayIcon();
    _refreshTaskbar();
    _rebuildMenu(); // fait apparaître/disparaître "Marquer comme lu"
  }

  Future<void> _onCinnyNotification(CinnyNotification notification) async {
    // Pas de toast Windows pour les messages : le badge et le clignotement
    // suffisent. On continue en revanche d'intercepter window.Notification
    // côté Cinny, c'est ce qui alimente le compteur.

    if (await _windowIsVisible()) {
      // Fenêtre présente dans la barre des tâches : on fait clignoter son
      // bouton jusqu'à ce qu'elle repasse au premier plan.
      try {
        WindowsTaskbar.setFlashTaskbarAppIcon(
          mode: TaskbarFlashMode.all | TaskbarFlashMode.timernofg,
          timeout: const Duration(milliseconds: 500),
        );
      } catch (e) {
        debugPrint('Clignotement barre des tâches indisponible : $e');
      }
    } else {
      _startBlinkBurst();
    }
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
    ];

    if (UnreadService.instance.status.value.hasUnread) {
      items.add(MenuItem(key: 'mark_seen', label: 'Marquer comme lu'));
    }
    items.add(MenuItem.separator());

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
        // Permet de forcer la vérification sans attendre le tick de 10 min,
        // et d'obtenir un message explicite quand rien n'est trouvé.
        items.add(MenuItem(key: 'check_update', label: 'Vérifier les mises à jour'));
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
      case 'mark_seen':
        UnreadService.instance.markSeen();
        break;
      case 'check_update':
        _notify('Mise à jour', await UpdateService.instance.checkForUpdate());
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
      // Plus de bouton dans la barre des tâches : la pastille bascule sur
      // l'icône du tray.
      await _refreshTrayIcon();
    }
  }

  @override
  void onWindowFocus() {
    // La pastille n'est PAS effacée ici : revenir sur la fenêtre ne veut pas
    // dire avoir lu les messages. C'est Cinny qui fait foi, via son favicon
    // (voir UnreadService.onFaviconState), et l'entrée "Marquer comme lu"
    // sert de secours.
    //
    // Occasion naturelle de re-vérifier les mises à jour, plutôt que
    // d'attendre le tick de 10 minutes.
    UpdateService.instance.checkForUpdate();
  }
}
