; Inno Setup 6 script for Qingya Windows desktop
; Source: flutter build windows --release output

#define MyAppName "Qingya"
#define MyAppPublisher "ynlea"
#define MyAppExeName "qingya.exe"
#define MyAppURL "https://github.com/ynlea/agent-status"
; 本地默认；CI 可用 ISCC /DMyAppVersion=x.y.z 覆盖
#ifndef MyAppVersion
  #define MyAppVersion "0.1.14"
#endif

[Setup]
AppId={{A7C3E9F1-2B4D-4E6A-9C8F-1D2E3F4A5B6C}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
DefaultDirName={autopf}\Qingya
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\build\windows
OutputBaseFilename=qingya-windows-setup
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop icon"; GroupDescription: "Additional icons:"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch Qingya"; Flags: nowait postinstall skipifsilent
