import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'remote_config_service.dart';

enum UpdatePhase { idle, available, downloading, readyToRestart, error }

class UpdateStatus {
  final UpdatePhase phase;
  final String? latestVersion;
  final double progress;
  final String? error;

  const UpdateStatus({
    this.phase = UpdatePhase.idle,
    this.latestVersion,
    this.progress = 0,
    this.error,
  });
}

/// Gère la détection et l'installation des mises à jour Windows.
///
/// Le fichier .exe d'installation est publié par la CI GitHub Actions sous
/// forme de GitHub Release taguée `v<version>` (voir build-windows.yml et
/// windows/installer.iss). L'admin ne fait que déclarer, via la console,
/// quelle version est "latest_version" dans remote_config.json — l'app en
/// déduit l'URL de téléchargement toute seule.
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  final ValueNotifier<UpdateStatus> status = ValueNotifier(const UpdateStatus());

  String? _downloadedInstallerPath;

  String _downloadUrlFor(String version) =>
      'https://github.com/${RemoteConfigConstants.owner}/${RemoteConfigConstants.repo}'
      '/releases/download/v$version/CinnyApp-Setup.exe';

  Future<void> checkForUpdate() async {
    if (!Platform.isWindows) return;
    // Un téléchargement ou une install en attente ne doit pas être
    // interrompu par un re-check périodique.
    final phase = status.value.phase;
    if (phase == UpdatePhase.downloading || phase == UpdatePhase.readyToRestart) {
      return;
    }

    final remote = await RemoteConfigService.fetch();
    final latest = remote?.latestVersion;
    if (latest == null || latest.isEmpty) return;

    final info = await PackageInfo.fromPlatform();
    if (_isNewer(latest, info.version)) {
      status.value = UpdateStatus(phase: UpdatePhase.available, latestVersion: latest);
    }
  }

  bool _isNewer(String latest, String current) {
    List<int> parse(String v) => v
        .split('.')
        .map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
    final a = parse(latest);
    final b = parse(current);
    for (var i = 0; i < a.length || i < b.length; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  /// Télécharge l'installeur (progression réelle basée sur Content-Length),
  /// sans encore rien installer.
  Future<void> downloadUpdate() async {
    final current = status.value;
    if (current.phase != UpdatePhase.available || current.latestVersion == null) {
      return;
    }
    final version = current.latestVersion!;
    final client = http.Client();
    try {
      status.value = UpdateStatus(phase: UpdatePhase.downloading, latestVersion: version, progress: 0);

      final response = await client.send(http.Request('GET', Uri.parse(_downloadUrlFor(version))));
      if (response.statusCode != 200) {
        throw Exception('Téléchargement impossible (HTTP ${response.statusCode})');
      }

      final total = response.contentLength ?? 0;
      var received = 0;
      final dir = await Directory.systemTemp.createTemp('cinny_update_');
      final file = File('${dir.path}${Platform.pathSeparator}CinnyApp-Setup.exe');
      final sink = file.openWrite();

      await for (final chunk in response.stream) {
        received += chunk.length;
        sink.add(chunk);
        status.value = UpdateStatus(
          phase: UpdatePhase.downloading,
          latestVersion: version,
          progress: total > 0 ? received / total : 0,
        );
      }
      await sink.close();

      _downloadedInstallerPath = file.path;
      status.value = UpdateStatus(phase: UpdatePhase.readyToRestart, latestVersion: version, progress: 1);
    } catch (e) {
      status.value = UpdateStatus(phase: UpdatePhase.error, latestVersion: version, error: '$e');
    } finally {
      client.close();
    }
  }

  /// Lance l'installeur en silencieux puis quitte immédiatement : Inno Setup
  /// se charge de fermer proprement l'app (déjà quittée à ce stade),
  /// remplacer les fichiers, et relancer Cinny automatiquement.
  Future<void> restartAndInstall() async {
    final path = _downloadedInstallerPath;
    if (path == null) return;
    await Process.start(
      path,
      [
        '/VERYSILENT',
        '/SUPPRESSMSGBOXES',
        '/NORESTART',
        '/CLOSEAPPLICATIONS',
        '/RESTARTAPPLICATIONS',
      ],
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }
}
