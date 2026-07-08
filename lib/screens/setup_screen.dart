import 'package:flutter/material.dart';
import '../services/config_service.dart';
import 'webview_screen.dart';

class SetupScreen extends StatefulWidget {
  /// Pré-remplissage optionnel (ex: valeur "default_url" trouvée dans la
  /// config distante), pour éviter à l'utilisateur de taper une URL à
  /// l'aveugle si l'admin en a déjà défini une.
  final String? prefillUrl;
  final String? infoMessage;

  const SetupScreen({super.key, this.prefillUrl, this.infoMessage});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late final TextEditingController _controller;
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.prefillUrl ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _validate(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Indique l\'adresse de ton serveur Cinny.';
    final uri = Uri.tryParse(v);
    if (uri == null || !uri.hasScheme || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return 'L\'adresse doit commencer par https:// (ou http://).';
    }
    return null;
  }

  Future<void> _continue() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final url = _controller.text.trim();
    await ConfigService.saveUserUrl(url);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => WebviewScreen(url: url)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.chat_bubble_outline_rounded,
                        size: 48, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      'Configuration initiale',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Indique l\'adresse de ton serveur Cinny. '
                      'Cette étape ne sera demandée qu\'une seule fois.',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    if (widget.infoMessage != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          widget.infoMessage!,
                          style: Theme.of(context).textTheme.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _controller,
                      autofocus: true,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'URL du serveur Cinny',
                        hintText: 'https://chat.mondomaine.fr',
                        border: OutlineInputBorder(),
                      ),
                      validator: _validate,
                      onFieldSubmitted: (_) => _continue(),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _saving ? null : _continue,
                      child: _saving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Continuer'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
