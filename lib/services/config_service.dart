import 'package:shared_preferences/shared_preferences.dart';

/// Gère l'URL du serveur Cinny choisie par l'utilisateur, sauvegardée
/// localement sur l'appareil (SharedPreferences = fichier local simple,
/// pas de compte ni de cloud impliqué ici).
class ConfigService {
  static const _keyUrl = 'cinny_server_url';
  static const _keyForcedByAdmin = 'cinny_url_forced_by_admin';

  /// Retourne l'URL sauvegardée, ou null si l'utilisateur n'a encore
  /// jamais configuré l'application (= premier lancement).
  static Future<String?> getSavedUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUrl);
  }

  /// Sauvegarde l'URL choisie par l'utilisateur lui-même (écran de
  /// première configuration, ou écran "changer de serveur").
  static Future<void> saveUserUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUrl, url.trim());
    await prefs.setBool(_keyForcedByAdmin, false);
  }

  /// Sauvegarde une URL imposée à distance par l'administrateur
  /// (mécanisme de secours). On note qu'elle vient de l'admin pour
  /// pouvoir, plus tard, l'afficher différemment si besoin.
  static Future<void> saveAdminForcedUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUrl, url.trim());
    await prefs.setBool(_keyForcedByAdmin, true);
  }

  static Future<bool> isCurrentUrlForcedByAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyForcedByAdmin) ?? false;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUrl);
    await prefs.remove(_keyForcedByAdmin);
  }
}
