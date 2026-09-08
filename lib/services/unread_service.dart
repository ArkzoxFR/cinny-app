import 'dart:async';

import 'package:flutter/foundation.dart';

/// État des messages non lus, alimenté par la webview Cinny.
///
/// Deux sources complémentaires (voir l'injection JS dans webview_screen.dart) :
///  - `window.Notification`, que Cinny appelle à chaque nouveau message : c'est
///    ce qui donne le compteur ;
///  - le favicon, que Cinny bascule sur cinny-unread.svg / cinny-highlight.svg :
///    filet de sécurité si les notifications sont désactivées côté Cinny, on
///    sait au moins qu'il y a quelque chose à lire.
class UnreadStatus {
  final int count;
  final bool highlight;

  const UnreadStatus({this.count = 0, this.highlight = false});

  bool get hasUnread => count > 0 || highlight;

  /// Libellé de la pastille : "1".."9", puis "9+".
  String? get badgeLabel {
    if (count <= 0) return highlight ? '1' : null;
    if (count > 9) return '9+';
    return '$count';
  }
}

class CinnyNotification {
  final String title;
  final String body;

  const CinnyNotification({required this.title, required this.body});
}

class UnreadService {
  UnreadService._();
  static final UnreadService instance = UnreadService._();

  final ValueNotifier<UnreadStatus> status = ValueNotifier(const UnreadStatus());

  final _notifications = StreamController<CinnyNotification>.broadcast();

  /// Chaque nouveau message signalé par Cinny, pour l'afficher en notification
  /// native Windows.
  Stream<CinnyNotification> get notifications => _notifications.stream;

  /// Un nouveau message est arrivé (une notification Cinny de plus).
  void onNotification({String? title, String? body}) {
    final current = status.value;
    status.value = UnreadStatus(count: current.count + 1, highlight: current.highlight);
    _notifications.add(CinnyNotification(
      title: (title == null || title.isEmpty) ? 'Cinny' : title,
      body: body ?? '',
    ));
  }

  /// Cinny a changé son favicon : 'none', 'unread' ou 'highlight'.
  ///
  /// C'est Cinny qui fait autorité sur "tout est lu" : dès qu'il repasse à
  /// 'none' (lecture ici ou depuis un autre appareil), on efface tout, badge
  /// et compteur compris.
  void onFaviconState(String state) {
    final current = status.value;

    if (state == 'none') {
      if (current.hasUnread) status.value = const UnreadStatus();
      return;
    }

    // 'unread' comme 'highlight' signifient tous deux qu'il reste quelque
    // chose à lire — la nuance mention/simple message ne change rien au badge.
    if (!current.highlight) {
      status.value = UnreadStatus(count: current.count, highlight: true);
    }
  }

  /// L'utilisateur revient sur la fenêtre : on considère qu'il a vu.
  void markSeen() {
    if (status.value.hasUnread) status.value = const UnreadStatus();
  }
}
