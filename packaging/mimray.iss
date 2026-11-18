; Windows installer (per-user, no admin): installs to %LOCALAPPDATA%\Programs\mimray
; (same place as install.ps1, so in-app updates keep working), Start Menu
; shortcut, uninstall entry. Built by tool/release.sh:
;   ISCC /DVersion=<ver> /DSrc=<Release dir> /DOut=<dist> packaging\mimray.iss
[Setup]
AppId={{6B1F0E3A-4E2C-4F6B-9A7E-6D2C1B0F9A41}
AppName=mimray
AppVersion={#Version}
AppPublisher=mimray
DefaultDirName={localappdata}\Programs\mimray
DisableProgramGroupPage=yes
DisableDirPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#Out}
OutputBaseFilename=mimray-{#Version}-windows-x64-setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\mimray.exe
Compression=lzma2
SolidCompression=yes
CloseApplications=force

[Tasks]
Name: desktopicon; Description: "Desktop shortcut"

[Files]
Source: "{#Src}\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{userprograms}\mimray"; Filename: "{app}\mimray.exe"
Name: "{userdesktop}\mimray"; Filename: "{app}\mimray.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\mimray.exe"; Description: "Launch mimray"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
