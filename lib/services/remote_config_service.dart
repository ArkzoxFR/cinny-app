import 'dart:convert';
import 'package:http/http.dart' as http;

/// ⚠️ À adapter si un jour tu changes de dépôt ou de branche.
/// C'est la seule chose codée "en dur" : l'adresse du fichier de config
/// que la page admin modifie, et que l'application va lire à chaque
/// démarrage.
class RemoteConfigConstants {
  static const owner = 'ArkzoxFR';
  static const repo = 'cinny-app';
  static const branch = 'main';
  static const path = 'config/remote_config.json';

  static String get rawUrl =>
      'https://raw.githubusercontent.com/$owner/$repo/$branch/$path';
}

class RemoteConfig {
  final String? defaultUrl;
  final String? forceUrl;
  final String? message;
  final bool maintenance;
  final String? latestVersion;

  const RemoteConfig({
    this.defaultUrl,
    this.forceUrl,
    this.message,
    this.maintenance = false,
    this.latestVersion,
  });

  factory RemoteConfig.fromJson(Map<String, dynamic> json) {
    return RemoteConfig(
      defaultUrl: (json['default_url'] as String?)?.trim(),
      forceUrl: (json['force_url'] as String?)?.trim(),
      message: (json['message'] as String?)?.trim(),
      maintenance: json['maintenance'] == true,
      latestVersion: (json['latest_version'] as String?)?.trim(),
    );
  }

  bool get hasForceUrl => forceUrl != null && forceUrl!.isNotEmpty;
}

/// Va chercher le fichier config/remote_config.json sur GitHub.
/// Ce fichier est modifié par la page /admin (ou à la main), et permet
/// de piloter à distance toutes les installations de l'app sans passer
/// par un store : c'est le "bouton de secours" si le serveur par défaut
/// est dans les choux.
class RemoteConfigService {
  /// Timeout volontairement court : si le réseau est mauvais ou que
  /// GitHub est injoignable, l'app ne doit JAMAIS bloquer l'utilisateur.
  /// On retombe simplement sur la config locale déjà connue.
  static const _timeout = Duration(seconds: 4);

  static Future<RemoteConfig?> fetch() async {
    try {
      // Anti-cache : raw.githubusercontent.com garde un cache CDN de
      // quelques minutes, le paramètre "t" force à contourner ce cache.
      final uri = Uri.parse(
        '${RemoteConfigConstants.rawUrl}?t=${DateTime.now().millisecondsSinceEpoch}',
      );

      final response = await http.get(uri).timeout(_timeout);
      if (response.statusCode != 200) return null;

      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return RemoteConfig.fromJson(data as Map<String, dynamic>);
    } catch (_) {
      // Pas de réseau, JSON invalide, timeout... on ignore silencieusement,
      // l'app doit continuer à fonctionner avec la config locale.
      return null;
    }
  }
}
