import 'package:flutter/material.dart';

import '../services/update_service.dart';

/// Icône de mise à jour dans la barre du haut : n'apparaît que lorsqu'il y a
/// quelque chose à signaler, et ouvre un petit panneau (message + bouton +
/// barre de progression) plutôt qu'une fenêtre modale qui bloquerait l'app
/// pendant le téléchargement.
class UpdateIndicator extends StatelessWidget {
  const UpdateIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UpdateStatus>(
      valueListenable: UpdateService.instance.status,
      builder: (context, status, _) {
        final icon = _iconFor(status.phase);
        if (icon == null) return const SizedBox.shrink();

        return IconButton(
          icon: icon,
          tooltip: 'Mise à jour',
          onPressed: () => _showPanel(context),
        );
      },
    );
  }

  Widget? _iconFor(UpdatePhase phase) {
    switch (phase) {
      case UpdatePhase.available:
        return const Icon(Icons.download_rounded);
      case UpdatePhase.downloading:
        return const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case UpdatePhase.readyToRestart:
        return const Icon(Icons.restart_alt_rounded);
      case UpdatePhase.error:
        return const Icon(Icons.error_outline_rounded);
      case UpdatePhase.idle:
        return null;
    }
  }

  void _showPanel(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.15),
      builder: (_) => const UpdatePanel(),
    );
  }
}

class UpdatePanel extends StatelessWidget {
  /// Permet de figer un état (banc d'essai / captures) ; en usage normal le
  /// panneau suit l'état réel du service.
  final UpdateStatus? statusOverride;

  const UpdatePanel({super.key, this.statusOverride});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.only(top: 64, right: 12),
        child: Material(
          color: theme.colorScheme.surface,
          elevation: 8,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 320,
            padding: const EdgeInsets.all(20),
            child: ValueListenableBuilder<UpdateStatus>(
              valueListenable: UpdateService.instance.status,
              builder: (context, liveStatus, _) {
                final status = statusOverride ?? liveStatus;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.system_update_rounded,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text('Mise à jour', style: theme.textTheme.titleSmall),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(_messageFor(status), style: theme.textTheme.bodyMedium),
                    if (status.phase == UpdatePhase.downloading) ...[
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: status.progress > 0 ? status.progress : null,
                          minHeight: 6,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${(status.progress * 100).clamp(0, 100).toStringAsFixed(0)} %',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 18),
                    _actionFor(context, status),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  String _messageFor(UpdateStatus status) {
    switch (status.phase) {
      case UpdatePhase.available:
        final v = status.latestVersion;
        return 'Une nouvelle mise à jour est disponible${v == null ? '' : ' (v$v)'}.';
      case UpdatePhase.downloading:
        return 'Téléchargement de la mise à jour en cours…';
      case UpdatePhase.readyToRestart:
        return 'La mise à jour nécessite le redémarrage de l\'application.';
      case UpdatePhase.error:
        return status.error ?? 'La mise à jour a échoué.';
      case UpdatePhase.idle:
        return 'L\'application est à jour.';
    }
  }

  Widget _actionFor(BuildContext context, UpdateStatus status) {
    switch (status.phase) {
      case UpdatePhase.available:
        return FilledButton(
          onPressed: () => UpdateService.instance.downloadUpdate(),
          child: const Text('Installer'),
        );
      case UpdatePhase.downloading:
        return const FilledButton(onPressed: null, child: Text('Installation…'));
      case UpdatePhase.readyToRestart:
        return FilledButton(
          onPressed: () => UpdateService.instance.restartAndInstall(),
          child: const Text('Redémarrer'),
        );
      case UpdatePhase.error:
        return FilledButton(
          onPressed: () => UpdateService.instance.checkForUpdate(),
          child: const Text('Réessayer'),
        );
      case UpdatePhase.idle:
        return TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Fermer'),
        );
    }
  }
}
