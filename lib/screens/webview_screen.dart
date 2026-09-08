import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../services/config_service.dart';
import '../services/remote_config_service.dart';
import '../services/unread_service.dart';
import '../widgets/update_indicator.dart';

/// Script injecté dans Cinny pour remonter les messages non lus à l'app.
///
/// Cinny signale un nouveau message de deux façons (cf. son
/// ClientNonUIFeatures.tsx) : il appelle `window.Notification`, et il bascule
/// son favicon sur cinny-unread.svg / cinny-highlight.svg. On écoute les deux :
/// le premier donne le compteur, le second sert de filet si l'utilisateur a
/// désactivé les notifications dans Cinny.
const String _kUnreadBridgeJs = r'''
(function () {
  if (window.__cinnyBridgeInstalled) return;
  window.__cinnyBridgeInstalled = true;

  function post(handler, payload) {
    try {
      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
        window.flutter_inappwebview.callHandler(handler, payload);
      }
    } catch (e) {}
  }

  // Cinny ne notifie que si Notification.permission vaut 'granted'. Dans une
  // webview il n'y a pas d'interface pour accorder cette permission, donc on
  // substitue notre propre implémentation : elle se déclare autorisée et
  // relaie chaque notification à l'application native.
  function CinnyNotification(title, options) {
    options = options || {};
    this.title = title;
    this.body = options.body || '';
    this.onclick = null;
    this.onclose = null;
    this.onerror = null;
    this.onshow = null;
    post('cinnyNotification', {
      title: String(title == null ? '' : title),
      body: String(options.body == null ? '' : options.body)
    });
  }
  CinnyNotification.prototype.close = function () {};
  CinnyNotification.prototype.addEventListener = function () {};
  CinnyNotification.prototype.removeEventListener = function () {};
  CinnyNotification.permission = 'granted';
  CinnyNotification.requestPermission = function (cb) {
    if (cb) cb('granted');
    return Promise.resolve('granted');
  };
  try {
    Object.defineProperty(window, 'Notification', {
      configurable: true,
      writable: true,
      value: CinnyNotification
    });
  } catch (e) {
    window.Notification = CinnyNotification;
  }

  // Les deux favicons "non lu" partagent un tracé absent du logo normal ;
  // on le cherche aussi dans le SVG décodé, car le bundler peut inliner
  // l'image en data-URI (auquel cas le nom de fichier disparaît).
  var UNREAD_PATH_MARKER = '10.5867';

  function faviconState() {
    var links = document.querySelectorAll('link[rel*="icon"]');
    var state = 'none';
    for (var i = 0; i < links.length; i++) {
      var href = links[i].getAttribute('href') || '';
      if (href.indexOf('highlight') !== -1) return 'highlight';
      if (href.indexOf('unread') !== -1) state = 'unread';
      else if (href.indexOf('data:') === 0 && href.indexOf('base64,') !== -1) {
        try {
          var svg = atob(href.split('base64,')[1]);
          if (svg.indexOf(UNREAD_PATH_MARKER) !== -1) state = 'unread';
        } catch (e) {}
      }
    }
    return state;
  }

  var lastState = null;
  function checkFavicon() {
    var s = faviconState();
    if (s !== lastState) {
      lastState = s;
      post('cinnyUnreadState', { state: s });
    }
  }

  function start() {
    checkFavicon();
    try {
      new MutationObserver(checkFavicon).observe(document.head, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ['href']
      });
    } catch (e) {}
    setInterval(checkFavicon, 5000);
  }

  if (document.head) start();
  else document.addEventListener('DOMContentLoaded', start);
})();
''';

class WebviewScreen extends StatefulWidget {
  final String url;
  final String? maintenanceMessage;

  const WebviewScreen({super.key, required this.url, this.maintenanceMessage});

  @override
  State<WebviewScreen> createState() => _WebviewScreenState();
}

class _WebviewScreenState extends State<WebviewScreen> {
  InAppWebViewController? _controller;
  bool _loading = true;
  bool _loadError = false;
  String? _lastErrorDetail;
  String? _bannerMessage;
  Timer? _remoteCheckTimer;

  @override
  void initState() {
    super.initState();
    _bannerMessage = widget.maintenanceMessage;

    // Revérifie la config distante toutes les 10 minutes pendant que
    // l'app est ouverte, pour appliquer un "force_url" d'urgence sans
    // attendre que l'utilisateur redémarre l'application.
    _remoteCheckTimer = Timer.periodic(const Duration(minutes: 10), (_) => _checkRemoteOverride());
  }

  @override
  void dispose() {
    _remoteCheckTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkRemoteOverride() async {
    final remote = await RemoteConfigService.fetch();
    if (remote == null || !mounted) return;

    if (remote.hasForceUrl && remote.forceUrl != widget.url) {
      await ConfigService.saveAdminForcedUrl(remote.forceUrl!);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => WebviewScreen(
            url: remote.forceUrl!,
            maintenanceMessage: remote.message ??
                'Le serveur a été mis à jour à distance par l\'administrateur.',
          ),
        ),
      );
    } else if (remote.message != null && remote.message != _bannerMessage) {
      setState(() => _bannerMessage = remote.message);
    }
  }

  Future<void> _changeServer() async {
    final currentUrl = await ConfigService.getSavedUrl();
    if (!mounted) return;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _ChangeServerDialog(currentUrl: currentUrl ?? widget.url),
    );

    if (result != null && result.isNotEmpty && mounted) {
      await ConfigService.saveUserUrl(result);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => WebviewScreen(url: result)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cinny'),
        actions: [
          const UpdateIndicator(),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recharger',
            onPressed: () => _controller?.reload(),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'change_server') _changeServer();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'change_server',
                child: Text('Changer de serveur'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_bannerMessage != null)
            MaterialBanner(
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
              content: Text(_bannerMessage!),
              actions: [
                TextButton(
                  onPressed: () => setState(() => _bannerMessage = null),
                  child: const Text('Masquer'),
                ),
              ],
            ),
          Expanded(
            child: Stack(
              children: [
                if (!_loadError)
                  InAppWebView(
                    initialUrlRequest: URLRequest(url: WebUri(widget.url)),
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      mediaPlaybackRequiresUserGesture: false,
                      useOnDownloadStart: true,
                      useShouldOverrideUrlLoading: true,
                    ),
                    initialUserScripts: UnmodifiableListView([
                      UserScript(
                        source: _kUnreadBridgeJs,
                        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                      ),
                    ]),
                    onWebViewCreated: (controller) {
                      _controller = controller;
                      controller.addJavaScriptHandler(
                        handlerName: 'cinnyNotification',
                        callback: (args) {
                          final data = args.isNotEmpty && args.first is Map
                              ? Map<String, dynamic>.from(args.first as Map)
                              : const <String, dynamic>{};
                          UnreadService.instance.onNotification(
                            title: (data['title'] as String?)?.trim(),
                            body: (data['body'] as String?)?.trim(),
                          );
                          return null;
                        },
                      );
                      controller.addJavaScriptHandler(
                        handlerName: 'cinnyUnreadState',
                        callback: (args) {
                          final data = args.isNotEmpty && args.first is Map
                              ? Map<String, dynamic>.from(args.first as Map)
                              : const <String, dynamic>{};
                          UnreadService.instance.onFaviconState(
                            (data['state'] as String?) ?? 'none',
                          );
                          return null;
                        },
                      );
                    },
                    shouldOverrideUrlLoading: (controller, navigationAction) async {
                      // useShouldOverrideUrlLoading exige ce callback : sans lui,
                      // la navigation (y compris le tout premier chargement) est
                      // annulée par défaut, quel que soit le site.
                      return NavigationActionPolicy.ALLOW;
                    },
                    onLoadStart: (controller, url) {
                      setState(() {
                        _loading = true;
                        _loadError = false;
                      });
                    },
                    onLoadStop: (controller, url) {
                      setState(() => _loading = false);
                      // Filet de sécurité : si initialUserScripts n'est pas
                      // honoré sur cette plateforme, on réinjecte ici. Le
                      // script se protège lui-même contre la double injection.
                      controller.evaluateJavascript(source: _kUnreadBridgeJs);
                    },
                    onReceivedError: (controller, request, error) {
                      if (request.isForMainFrame ?? true) {
                        setState(() {
                          _loading = false;
                          _loadError = true;
                          _lastErrorDetail = '${error.type} — ${error.description}';
                        });
                      }
                    },
                    onReceivedHttpError: (controller, request, response) {
                      if (request.isForMainFrame ?? true) {
                        setState(() {
                          _loading = false;
                          _loadError = true;
                          _lastErrorDetail = 'HTTP ${response.statusCode}';
                        });
                      }
                    },
                  ),
                if (_loading && !_loadError)
                  const Center(child: CircularProgressIndicator()),
                if (_loadError)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_off_rounded, size: 48),
                          const SizedBox(height: 12),
                          Text(
                            'Impossible de joindre :\n${widget.url}',
                            textAlign: TextAlign.center,
                          ),
                          if (_lastErrorDetail != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              _lastErrorDetail!,
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: Theme.of(context).colorScheme.error),
                            ),
                          ],
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () {
                              setState(() => _loadError = false);
                              _controller?.reload();
                            },
                            child: const Text('Réessayer'),
                          ),
                          TextButton(
                            onPressed: _changeServer,
                            child: const Text('Changer de serveur'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChangeServerDialog extends StatefulWidget {
  final String currentUrl;
  const _ChangeServerDialog({required this.currentUrl});

  @override
  State<_ChangeServerDialog> createState() => _ChangeServerDialogState();
}

class _ChangeServerDialogState extends State<_ChangeServerDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentUrl);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _controller.text.trim();
    final uri = Uri.tryParse(v);
    if (uri == null || !uri.hasScheme || !(uri.isScheme('http') || uri.isScheme('https'))) {
      setState(() => _error = 'Adresse invalide (doit commencer par https://)');
      return;
    }
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Changer de serveur'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.url,
        decoration: InputDecoration(
          labelText: 'URL du serveur Cinny',
          errorText: _error,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Enregistrer')),
      ],
    );
  }
}
