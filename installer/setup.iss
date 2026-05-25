[Setup]
AppName=MyARAP
AppVersion=1.0.0
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

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\MyARAP"; Filename: "{app}\myarap.exe"
Name: "{group}\Uninstall MyARAP"; Filename: "{uninstallexe}"
Name: "{autodesktop}\MyARAP"; Filename: "{app}\myarap.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\myarap.exe"; Description: "Launch MyARAP"; Flags: nowait postinstall skipifsilent
