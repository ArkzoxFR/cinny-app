# cinny-app

Une app qui garde Cinny (le chat Matrix) à portée de main sans avoir à laisser
un onglet de navigateur ouvert en permanence — sur Windows, elle vit dans la
barre des tâches : fermer la fenêtre ne quitte pas l'app, l'icône reste là, et
un clic la fait réapparaître instantanément. Plus besoin de fouiller entre dix
onglets pour retrouver sa messagerie, ni de se demander si le navigateur a
mangé l'onglet en arrière-plan.

Les mises à jour de l'app se signalent aussi toutes seules (icône + notification
dans la barre des tâches) et s'installent en un clic, sans jamais avoir à aller
chercher un nouvel exécutable à la main.

Client Cinny (Matrix) pour **Android, iOS et Windows**, avec en plus :
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
  services/tray_service.dart          → icône barre des tâches (Windows)
  services/update_service.dart        → détection/téléchargement des MAJ (Windows)
  services/unread_service.dart        → compteur de messages non lus
  widgets/update_indicator.dart       → icône + panneau de mise à jour
config/remote_config.json       → fichier piloté par la console admin
admin/index.html                → console d'admin (hébergée sur GitHub Pages)
windows/installer.iss           → script Inno Setup (génère CinnyApp-Setup.exe)
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

La page `admin/index.html` est un fichier statique, hébergée gratuitement avec
**GitHub Pages** directement depuis ce dépôt (déjà activé) :
**https://arkzoxfr.github.io/cinny-app/admin/**

Ça ne fonctionne que parce que le dépôt est **public** — GitHub Pages gratuit
et la lecture de `config/remote_config.json` via `raw.githubusercontent.com`
(sans authentification, voir plus haut) l'exigent tous les deux. Aucun secret
n'est stocké dans le dépôt : le token admin reste local au navigateur.

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

## Windows : icône barre des tâches et mises à jour

L'app Windows (`lib/services/tray_service.dart` + `update_service.dart`) reste
active dans la barre des tâches quand on ferme la fenêtre (la croix masque au
lieu de quitter) ; clic droit sur l'icône propose "Ouvrir Cinny" et "Quitter"
(le seul vrai moyen de fermer l'app), plus l'état de la mise à jour en cours.
L'icône bascule automatiquement entre une version blanche et une version
sombre selon le thème clair/sombre de Windows (`assets/tray_icon_light.ico` /
`tray_icon_dark.ico`), pour rester lisible sur les deux.

### Messages non lus

Quand un message arrive, une notification Windows native s'affiche et un badge
rouge numéroté (1 à 9, puis 9+) signale les messages non lus. Où il apparaît
dépend de l'état de la fenêtre :

- **fenêtre ouverte** : badge sur le **bouton de la barre des tâches**
  (overlay icon), et le bouton clignote jusqu'à ce que la fenêtre revienne au
  premier plan — comme Teams (`windows_taskbar`) ;
- **fenêtre masquée** (fermée vers le tray) : il n'y a plus de bouton dans la
  barre des tâches, la pastille bascule donc sur l'icône du tray, qui clignote
  par salves de ~8 s.

Tout repart à zéro dès que la fenêtre reprend le focus.

La détection se fait dans la webview (`_kUnreadBridgeJs` dans
`webview_screen.dart`), en s'appuyant sur deux signaux émis par Cinny lui-même
(cf. son `ClientNonUIFeatures.tsx`) :

- `window.Notification`, appelé à chaque nouveau message — c'est ce qui
  alimente le compteur. Le script substitue sa propre implémentation, qui se
  déclare autorisée (une webview n'a pas d'interface pour accorder la
  permission de notification) et relaie tout à l'app native.
- le favicon, que Cinny bascule sur `cinny-unread.svg` / `cinny-highlight.svg` —
  filet de sécurité si l'utilisateur a désactivé les notifications dans les
  réglages de Cinny : on sait alors au moins qu'il y a quelque chose à lire,
  sans connaître le nombre.

Les icônes de badge sont pré-générées (`assets/badge_N.ico` pour la barre des
tâches, `assets/tray_icon_{light,dark}_N.ico` pour le tray) plutôt que composées
à l'exécution : les API Windows concernées attendent un chemin de fichier `.ico`.

Publier une mise à jour Windows, entièrement depuis la console admin (rien à
faire côté code/terminal) :

1. Ouvre la console admin, section "Mise à jour Windows", indique le nouveau
   numéro de version (ex. `1.0.2`), clique "Construire et publier".
2. La console bump elle-même la version dans `pubspec.yaml` via l'API GitHub,
   attend que la CI (`build-windows.yml`) build l'app et génère l'installeur
   avec **Inno Setup** (`windows/installer.iss`) — publié automatiquement
   comme **GitHub Release** taguée `v1.0.2` (`CinnyApp-Setup.exe`, install par
   utilisateur, sans droits admin) — puis, si le build est vert, publie
   automatiquement `latest_version` dans `remote_config.json`. Ça prend
   5 à 8 minutes, suivi en direct dans la console.
3. Dans les 10 minutes suivantes, toutes les applis installées détectent que
   `latest_version` > leur version locale (`package_info_plus`) : l'icône
   tray notifie "Mise à jour disponible" et propose "Installer la mise à
   jour" (télécharge l'installeur avec barre de progression). Une fois
   téléchargé, le menu propose "Redémarrer" : l'app se ferme, l'installeur
   tourne en silencieux, et relance Cinny automatiquement.

(L'option avancée "republier une version déjà construite" dans la console
reste utile pour re-notifier ou revenir à une version dont l'installeur
existe déjà, sans relancer un build.)

Étape 3 est volontairement manuelle (l'admin garde la main sur qui reçoit
quoi et quand), même si l'étape 2 est déjà automatique à chaque push.

## Limites à connaître

- **iOS** : Apple impose un compte Apple Developer (payant) et une signature
  pour installer l'app sur un vrai iPhone ou la publier sur l'App Store /
  TestFlight. Le workflow `build-ios.yml` compile l'app pour vérifier qu'elle
  fonctionne, mais reste **non signée**. Dis-moi quand tu seras prêt pour cette
  étape, on ajoutera tes certificats en secrets GitHub.
- Le mécanisme distant sert à changer **la configuration** (l'URL du serveur),
  pas à pousser du nouveau code exécutable dans une app déjà installée — ce
  n'est techniquement pas permis sur iOS/Android par les stores. Sur Windows
  en revanche, le vrai code change bien (voir section ci-dessus) puisqu'on ne
  passe pas par un store.
- **`CinnyApp-Setup.exe` n'est pas signé** (pas de certificat de signature de
  code, payant). Windows SmartScreen affichera un avertissement "Éditeur
  inconnu" au premier lancement — normal, il faut cliquer sur "Informations
  complémentaires" → "Exécuter quand même". Dis-moi si tu veux qu'on ajoute
  une signature plus tard.
