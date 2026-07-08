import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../services/config_service.dart';
import '../services/remote_config_service.dart';

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
                    onWebViewCreated: (controller) => _controller = controller,
                    onLoadStart: (controller, url) {
                      setState(() {
                        _loading = true;
                        _loadError = false;
                      });
                    },
                    onLoadStop: (controller, url) {
                      setState(() => _loading = false);
                    },
                    onReceivedError: (controller, request, error) {
                      if (request.isForMainFrame ?? true) {
                        setState(() {
                          _loading = false;
                          _loadError = true;
                          _lastErrorDetail = '${error.type.name} — ${error.description}';
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
