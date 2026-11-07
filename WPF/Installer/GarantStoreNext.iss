#define ProductName "Garant Store Next"
#define ProductVersion "0.11.0 Preview"

[Setup]
AppId={{8F2F7DC0-F113-4B09-8855-390F301E7A34}
AppName={#ProductName}
AppVersion={#ProductVersion}
AppVerName={#ProductName} {#ProductVersion}
AppPublisher=Ибрагим Сугаипов
AppPublisherURL=https://instagram.com/master.vu95
AppSupportURL=https://wa.me/79287454249
AppUpdatesURL=mailto:g-garant95@mail.ru
DefaultDirName={autopf}\Garant Store Next
DefaultGroupName=Garant Store
UninstallDisplayName={#ProductName}
UninstallDisplayIcon={app}\Assets\GarantStoreMark.ico
SetupIconFile=..\Assets\GarantStoreMark.ico
OutputDir=..\dist
OutputBaseFilename=GarantStore-Setup
VersionInfoVersion=0.11.0.1
VersionInfoProductName={#ProductName}
VersionInfoProductVersion=0.11.0.1
VersionInfoCompany=Ибрагим Сугаипов
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes
CloseApplications=force
RestartApplications=no

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "Создать ярлык на рабочем столе"; GroupDescription: "Дополнительные ярлыки:"; Flags: unchecked

[Files]
Source: "..\GarantStore*.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\AboutWindow.xaml"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\DriverWindow.xaml"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\GarantStore.Drivers.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\GarantStore.Launcher.vbs"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\BuildInfo.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\Start-GarantStore-Next.cmd"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\DONATIONS.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\DESIGN-CREDITS.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\Assets\GarantStoreMark.svg"; DestDir: "{app}\Assets"; Flags: ignoreversion
Source: "..\Assets\GarantStoreMark.png"; DestDir: "{app}\Assets"; Flags: ignoreversion
Source: "..\Assets\GarantStoreMark.ico"; DestDir: "{app}\Assets"; Flags: ignoreversion
Source: "..\DriverEngine\*"; DestDir: "{app}\DriverEngine"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Garant Store"; Filename: "{sys}\wscript.exe"; Parameters: "//B ""{app}\GarantStore.Launcher.vbs"""; WorkingDir: "{app}"; IconFilename: "{app}\Assets\GarantStoreMark.ico"; AppUserModelID: "GarantStore.Next.Desktop"
Name: "{autodesktop}\Garant Store"; Filename: "{sys}\wscript.exe"; Parameters: "//B ""{app}\GarantStore.Launcher.vbs"""; WorkingDir: "{app}"; IconFilename: "{app}\Assets\GarantStoreMark.ico"; AppUserModelID: "GarantStore.Next.Desktop"; Tasks: desktopicon

[Run]
Filename: "{sys}\wscript.exe"; Parameters: "//B ""{app}\GarantStore.Launcher.vbs"""; WorkingDir: "{app}"; Description: "Запустить Garant Store"; Flags: postinstall nowait skipifsilent runasoriginaluser
