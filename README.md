# cinny-app

Client Cinny (Matrix) pour **Android, iOS et Windows**, avec :
- une configuration du serveur demandée une seule fois au premier lancement ;
- un fichier de configuration distant, hébergé sur ce dépôt GitHub, qui permet de
  **changer le serveur de toutes les installations déjà faites, sans réinstaller
  l'app** ;
- une petite console d'admin (page web statique) pour piloter ce fichier sans
  toucher au code.

## Comment ça marche (vue d'ensemble)

Il y a deux mécanismes bien séparés, ne les confonds pas :

1. **Le code de l'app** (dans `lib/`) : c'est le vrai code Flutter. Pour le mettre
   à jour, il faut recompiler et redistribuer l'app (Play Store, App Store, ou un
   .exe Windows) — comme pour n'importe quelle application. Les workflows dans
   `.github/workflows/` s'en chargent automatiquement à chaque `git push` (voir
   plus bas).
2. **La configuration serveur** (`config/remote_config.json`) : c'est un simple
   fichier JSON sur ce dépôt. L'app le relit à chaque démarrage (et toutes les
   10 minutes si elle reste ouverte). Si tu y mets une valeur dans `force_url`,
   **toutes les applis déjà installées basculent dessus automatiquement** —
   c'est le bouton de secours si ton serveur Cinny tombe.

Concrètement : le "premier lancement" fonctionne comme ça :
`démarrage → lit l'URL sauvegardée localement → interroge remote_config.json →
si force_url est rempli, il gagne toujours → sinon, s'il y a déjà une URL locale,
on l'utilise → sinon, écran de configuration (pré-rempli avec default_url si
présent)`.

## Ce que contient ce pack

```
lib/
  main.dart                     → logique de démarrage (setup vs webview)
  screens/setup_screen.dart     → écran "premier lancement"
  screens/webview_screen.dart   → écran principal (webview + changement manuel)
  services/config_service.dart        → stockage local de l'URL
  services/remote_config_service.dart → lecture du JSON distant sur GitHub
config/remote_config.json       → fichier piloté par la console admin
admin/index.html                → console d'admin (à héberger sur GitHub Pages)
.github/workflows/              → build auto Android / Windows / iOS
pubspec.yaml                    → dépendances Flutter
```

**Important** : je ne t'ai pas généré les dossiers `android/`, `ios/` et
`windows/` (ceux générés par Flutter lui-même), parce que je n'ai pas Flutter
installé dans mon environnement pour les créer proprement. C'est la seule étape
manuelle, elle prend 2 minutes (voir ci-dessous).

## Mise en route (une seule fois)

1. Installe le [SDK Flutter](https://docs.flutter.dev/get-started/install) sur
   ton PC si ce n'est pas déjà fait.
2. Clone ton dépôt vide :
   ```bash
   git clone https://github.com/ArkzoxFR/cinny-app.git
   cd cinny-app
   ```
3. Génère le squelette natif des 3 plateformes directement dedans :
   ```bash
   flutter create --platforms=android,ios,windows --project-name cinny_app .
   ```
   Cela va créer les dossiers `android/`, `ios/`, `windows/` et un `lib/main.dart`
   par défaut — pas de souci, on va écraser ce dernier avec le nôtre.
4. Copie par-dessus les fichiers de ce pack (`lib/`, `config/`, `admin/`,
   `.github/`, et remplace `pubspec.yaml` et `.gitignore` par les miens).
5. Récupère les dépendances :
   ```bash
   flutter pub get
   ```
6. Teste en local :
   ```bash
   flutter run -d windows     # ou -d chrome, ou un appareil Android/iOS branché
   ```
7. Renseigne une vraie URL dans `config/remote_config.json` (`default_url`), puis
   pousse tout :
   ```bash
   git add .
   git commit -m "Mise en place de l'app"
   git push
   ```
   → ça déclenche automatiquement les builds Android et Windows dans l'onglet
   **Actions** de GitHub. Les fichiers compilés (APK, .zip Windows) sont
   téléchargeables comme "artifacts" du run.

## Activer la console d'admin

La page `admin/index.html` est un fichier statique : le plus simple est de
l'héberger avec **GitHub Pages**, gratuitement, directement depuis ce dépôt.

1. Sur GitHub : `Settings` → `Pages` → `Source: Deploy from a branch` → branche
   `main`, dossier `/ (root)` (ou déplace `admin/index.html` vers `docs/index.html`
   si tu préfères utiliser le dossier `docs`).
2. GitHub te donne une URL du type `https://arkzoxfr.github.io/cinny-app/admin/`.
3. Crée un **token GitHub fine-grained** dédié :
   `Settings` (de ton compte) → `Developer settings` → `Fine-grained tokens` →
   `Generate new token` → limite-le au dépôt `cinny-app` uniquement, avec la
   permission **Contents: Read and write**. Rien d'autre.
4. Ouvre la console, colle ce token, et tu peux :
   - changer le **serveur par défaut** (ce qui est proposé au premier lancement) ;
   - **forcer** un serveur pour tout le monde en cas de pépin (bascule visible,
     avec un liseré orange sur la console tant que c'est actif) ;
   - afficher un **message** (ex. "maintenance en cours") ;
   - marquer l'app en **maintenance**.

Le token reste uniquement dans ton navigateur (envoyé seulement à
`api.github.com`) — il n'est jamais stocké ailleurs que sur ton appareil, et
seulement si tu coches "se souvenir".

## Limites à connaître

- **iOS** : Apple impose un compte Apple Developer (payant) et une signature
  pour installer l'app sur un vrai iPhone ou la publier sur l'App Store /
  TestFlight. Le workflow `build-ios.yml` compile l'app pour vérifier qu'elle
  fonctionne, mais reste **non signée**. Dis-moi quand tu seras prêt pour cette
  étape, on ajoutera tes certificats en secrets GitHub.
- Le mécanisme distant sert à changer **la configuration** (l'URL du serveur),
  pas à pousser du nouveau code exécutable dans une app déjà installée — ce
  n'est techniquement pas permis sur iOS/Android par les stores, et c'est aussi
  plus sûr ainsi. Pour un vrai changement de code, il faut une nouvelle version
  buildée (les workflows GitHub Actions s'en chargent) puis publiée/réinstallée.
