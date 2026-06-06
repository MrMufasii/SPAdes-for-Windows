; ============================================================================
; SPAdes for Windows (native port) - one-click installer
;
; Builds a single self-contained Setup .exe that bundles:
;   * the static spades-*.exe binaries (no DLLs, no WSL/Docker)
;   * share\spades (configs, HMM profiles, pyyaml3, spades_pipeline, test data)
;   * an embedded Python 3.11 (no system Python needed)
;   * .bat launchers for every mode + a "SPAdes Command Prompt"
;
; Invoked by build_spades_installer.ps1, which passes the payload location:
;   ISCC.exe /DPayloadDir=<dir> /DOutputDir=<dir> /DAppVersion=<ver> spades_windows.iss
;
; Per-user install by default (no admin), can elevate to all-users.
; ============================================================================

#ifndef PayloadDir
  #define PayloadDir "..\..\..\spades-dist\payload"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist"
#endif
#ifndef AppVersion
  #define AppVersion "4.3.0-dev"
#endif

#define MyAppName "SPAdes for Windows"
#define MyAppPublisher "SPAdes native-Windows port"
#define MyAppURL "https://github.com/MrMufasii/spades-windows-final"

[Setup]
AppId={{B6C1E0A2-7F2A-4E2D-9C3B-5A1D2E3F4A50}
AppName={#MyAppName}
AppVersion={#AppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
DefaultDirName={autopf}\SPAdes-Windows
DefaultGroupName=SPAdes for Windows
DisableProgramGroupPage=yes
DisableDirPage=no
LicenseFile={#PayloadDir}\share\spades\LICENSE
OutputDir={#OutputDir}
OutputBaseFilename=SPAdes-Windows-{#AppVersion}-Setup
Compression=lzma2/max
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
WizardStyle=modern
ChangesEnvironment=yes
UninstallDisplayName={#MyAppName}
UninstallDisplayIcon={sys}\cmd.exe

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "addtopath"; Description: "Add SPAdes to my PATH (run 'spades' from any terminal)"; GroupDescription: "Integration:"

[Files]
Source: "{#PayloadDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\SPAdes Command Prompt"; Filename: "{app}\spades-shell.bat"; WorkingDir: "{userdocs}"; IconFilename: "{sys}\cmd.exe"; Comment: "Open a terminal with SPAdes ready to use"
Name: "{group}\SPAdes Read Me"; Filename: "{app}\README-WINDOWS.txt"
Name: "{group}\Uninstall SPAdes"; Filename: "{uninstallexe}"

[Run]
Filename: "{app}\spades-shell.bat"; Description: "Open the SPAdes Command Prompt now"; Flags: postinstall skipifsilent nowait

[Code]
const EnvironmentKey = 'Environment';

function PathContains(const Paths, Dir: string): Boolean;
begin
  Result := Pos(';' + Uppercase(Dir) + ';', ';' + Uppercase(Paths) + ';') > 0;
end;

procedure AddToUserPath(const Dir: string);
var
  Paths: string;
begin
  if not RegQueryStringValue(HKEY_CURRENT_USER, EnvironmentKey, 'Path', Paths) then
    Paths := '';
  if PathContains(Paths, Dir) then
    exit;
  if (Paths <> '') and (Paths[Length(Paths)] <> ';') then
    Paths := Paths + ';';
  Paths := Paths + Dir;
  RegWriteExpandStringValue(HKEY_CURRENT_USER, EnvironmentKey, 'Path', Paths);
end;

procedure RemoveFromUserPath(const Dir: string);
var
  Paths, Rebuilt, Part: string;
  P: Integer;
begin
  if not RegQueryStringValue(HKEY_CURRENT_USER, EnvironmentKey, 'Path', Paths) then
    exit;
  if not PathContains(Paths, Dir) then
    exit;
  Rebuilt := '';
  Paths := Paths + ';';
  repeat
    P := Pos(';', Paths);
    Part := Copy(Paths, 1, P - 1);
    Paths := Copy(Paths, P + 1, Length(Paths));
    if (Part <> '') and (Uppercase(Part) <> Uppercase(Dir)) then
    begin
      if Rebuilt <> '' then
        Rebuilt := Rebuilt + ';';
      Rebuilt := Rebuilt + Part;
    end;
  until Paths = '';
  RegWriteExpandStringValue(HKEY_CURRENT_USER, EnvironmentKey, 'Path', Rebuilt);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
    if WizardIsTaskSelected('addtopath') then
      AddToUserPath(ExpandConstant('{app}\bin'));
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
    RemoveFromUserPath(ExpandConstant('{app}\bin'));
end;
