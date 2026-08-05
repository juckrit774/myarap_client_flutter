[Setup]
AppName=MyARAP
AppVersion=1.0.0.6
AppPublisher=ARSoft Mobile
DefaultDirName={autopf}\MyARAP
DefaultGroupName=MyARAP
OutputDir=installer_output
OutputBaseFilename=MyARAP_Setup
Compression=lzma
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"; Flags: unchecked
Name: "autostart"; Description: "Launch MyARAP when the computer starts"; GroupDescription: "Auto-start:"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\MyARAP"; Filename: "{app}\myarap.exe"
Name: "{group}\Uninstall MyARAP"; Filename: "{uninstallexe}"
Name: "{autodesktop}\MyARAP"; Filename: "{app}\myarap.exe"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "MyARAP"; ValueData: "{app}\myarap.exe"; Tasks: autostart

[Run]
Filename: "{app}\myarap.exe"; Description: "Launch MyARAP"; Flags: nowait postinstall skipifsilent
