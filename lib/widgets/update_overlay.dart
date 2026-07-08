import 'package:flutter/material.dart';

import '../services/update_service.dart';

/// Petite fenêtre modale affichée par-dessus l'appli pendant le
/// téléchargement d'une mise à jour, avec une barre de progression.
/// Non fermable : on attend que le téléchargement se termine (ou échoue).
class UpdateOverlay extends StatelessWidget {
  const UpdateOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UpdateStatus>(
      valueListenable: UpdateService.instance.status,
      builder: (context, status, _) {
        if (status.phase != UpdatePhase.downloading) {
          return const SizedBox.shrink();
        }
        final percent = (status.progress * 100).clamp(0, 100).toStringAsFixed(0);
        return Positioned.fill(
          child: Material(
            color: Colors.black.withValues(alpha: 0.55),
            child: Center(
              child: Container(
                width: 360,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [BoxShadow(blurRadius: 24, color: Colors.black38)],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.system_update_rounded,
                      size: 40,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Téléchargement de la mise à jour',
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Version ${status.latestVersion}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 20),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: status.progress > 0 ? status.progress : null,
                        minHeight: 8,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text('$percent %', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
