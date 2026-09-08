; Script Inno Setup pour Cinny (Windows).
; Compilé par la CI (.github/workflows/build-windows.yml) avec :
;   iscc /DAppVersion=1.2.3 windows\installer.iss
; AppVersion est fourni en ligne de commande pour rester synchronisé avec
; pubspec.yaml sans dupliquer le numéro de version ici.
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
; GUID fixe : NE JAMAIS changer, c'est ce qui permet à Inno Setup de
; reconnaître une réinstallation comme une mise à jour de la même app
; plutôt que d'installer une deuxième copie à côté.
AppId={{7C792CAB-026A-42BE-844E-C955948E56A1}
AppName=Cinny
AppVersion={#AppVersion}
AppPublisher=ArkzoxFR
DefaultDirName={localappdata}\CinnyApp
DefaultGroupName=Cinny
DisableProgramGroupPage=yes
; Installation par utilisateur, sans droits admin : indispensable pour que
; la mise à jour silencieuse déclenchée depuis l'app elle-même fonctionne
; sans invite UAC.
PrivilegesRequired=lowest
OutputDir=installer_output
OutputBaseFilename=CinnyApp-Setup
Compression=lzma2
SolidCompression=yes
SetupIconFile=runner\resources\app_icon.ico
UninstallDisplayIcon={app}\cinny_app.exe
; Permet à l'installeur de fermer Cinny s'il tourne (première install ou
; mise à jour manuelle) et de le relancer ensuite si demandé en ligne de
; commande (/RESTARTAPPLICATIONS, utilisé par le flux d'auto-MAJ interne).
CloseApplications=yes
CloseApplicationsFilter=cinny_app.exe
RestartApplications=yes

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "Créer une icône sur le Bureau"; GroupDescription: "Icônes supplémentaires :"

[Files]
; Chemin relatif au script (windows\installer.iss), donc "..\" pour remonter
; à la racine du projet où "flutter build windows" écrit sa sortie.
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{group}\Cinny"; Filename: "{app}\cinny_app.exe"
Name: "{autodesktop}\Cinny"; Filename: "{app}\cinny_app.exe"; Tasks: desktopicon

[Run]
; Install manuelle interactive : case à cocher "Lancer Cinny" en fin d'assistant.
Filename: "{app}\cinny_app.exe"; Description: "Lancer Cinny"; Flags: nowait postinstall skipifsilent runasoriginaluser

; Mise à jour silencieuse déclenchée depuis l'app : il faut relancer Cinny
; nous-mêmes. On ne peut pas compter sur /RESTARTAPPLICATIONS (il ne relance
; que les applications que l'installeur a lui-même fermées, or l'app a déjà
; quitté), ni sur l'entrée ci-dessus (le drapeau "postinstall" implique
; "skipifsilent" par défaut, donc elle est ignorée en mode silencieux).
Filename: "{app}\cinny_app.exe"; Flags: nowait runasoriginaluser; Check: WizardSilent
