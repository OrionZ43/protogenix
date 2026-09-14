; windows/installer/protogenix.iss
;
; Установщик Protogenix для Windows (Inno Setup 6).
;
; Ставится в профиль пользователя без прав администратора и без выбора папки:
;   %LOCALAPPDATA%\Programs\Protogenix
; Данные пользователя лежат отдельно — %LOCALAPPDATA%\Z43 Studios\Protogenix
; (.claude/rules/data.md). Установщик и деинсталлятор их не трогают.
;
; Сборка: tool/build_windows_installer.ps1, или вручную из этой папки:
;   iscc /DAppVersion=1.0.1 protogenix.iss
;
; Тихое обновление из приложения (lib/features/updater/update_installer.dart):
;   Protogenix-Setup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /update=1 /LOG=...
; Установщик ждёт, пока приложение закроется, заменяет файлы (при сбое
; Inno Setup откатывает изменения) и с /update=1 запускает приложение снова.

#ifndef AppVersion
  #error Не задана версия: iscc /DAppVersion=X.Y.Z protogenix.iss
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\build\installer"
#endif

#define AppName "Protogenix"
#define AppPublisher "Z43 Studios"
#define AppExeName "protogenix.exe"
; Совпадает с kSingleInstanceMutex в windows/runner/main.cpp.
#define AppMutexName "Z43Studios.Protogenix.SingleInstance"

[Setup]
; AppId — постоянный идентификатор установки. НИКОГДА не менять: по нему
; новая версия находит и обновляет старую.
AppId={{7405256B-0335-49E5-B937-184B687CF2CF}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL=https://z43-studios.vercel.app/
AppSupportURL=https://github.com/OrionZ43/protogenix
AppUpdatesURL=https://github.com/OrionZ43/protogenix/releases
VersionInfoVersion={#AppVersion}
VersionInfoCompany={#AppPublisher}
VersionInfoProductName={#AppName}
PrivilegesRequired=lowest
DefaultDirName={autopf}\{#AppName}
; Папку не выбираем: установщик чистит в ней файлы прошлой версии
; (см. [InstallDelete]), чужая папка под это попасть не должна.
DisableDirPage=yes
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
CloseApplications=force
RestartApplications=no
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName={#AppName}
OutputDir={#OutputDir}
OutputBaseFilename=Protogenix-Setup-{#AppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
SetupLogging=yes

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[InstallDelete]
; Файлы прошлой версии, которых может не быть в новой: ассеты Flutter
; и DLL плагинов. Пользовательских данных в папке программы нет.
Type: filesandordirs; Name: "{app}\data"
Type: files; Name: "{app}\*.dll"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Registry]
; Схема protogenix:// — «Слушать в Protogenix» со страницы сайта
; (lib/features/listen/domain/listen_link.dart). В профиле пользователя, прав
; администратора не нужно; удаляется вместе с программой.
Root: HKCU; Subkey: "Software\Classes\protogenix"; ValueType: string; ValueName: ""; ValueData: "URL:Protogenix"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\protogenix"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\protogenix\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#AppExeName},0"
Root: HKCU; Subkey: "Software\Classes\protogenix\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExeName}"" ""%1"""

[Run]
; Обычная установка — флажок «Запустить» на последней странице.
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent
; Тихое обновление из приложения (/update=1) — запустить сразу.
Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"; Flags: nowait; Check: IsUpdateRun

[Code]
const
  AppMutexName = '{#AppMutexName}';

function IsUpdateRun: Boolean;
begin
  Result := ExpandConstant('{param:update|0}') = '1';
end;

{ Ждёт, пока приложение закроется. True — закрылось. }
function WaitForAppExit(TimeoutMs: Integer): Boolean;
var
  Waited: Integer;
begin
  Waited := 0;
  while CheckForMutexes(AppMutexName) and (Waited < TimeoutMs) do
  begin
    Sleep(250);
    Waited := Waited + 250;
  end;
  Result := not CheckForMutexes(AppMutexName);
end;

{ Просит закрыть приложение, пока оно запущено. False — пользователь отказался. }
function AskToCloseApp(const Action: String): Boolean;
begin
  Result := True;
  while CheckForMutexes(AppMutexName) do
    if MsgBox('Protogenix сейчас запущен. Закрой его и нажми «OK», чтобы ' +
      Action + '.', mbInformation, MB_OKCANCEL) = IDCANCEL then
    begin
      Result := False;
      Exit;
    end;
end;

function InitializeSetup: Boolean;
begin
  if WizardSilent then
  begin
    { Тихое обновление: приложение закрывается само сразу после запуска
      установщика, ждём до 15 секунд. }
    Result := WaitForAppExit(15000);
    if not Result then
      Log('Protogenix всё ещё запущен — установка отменена');
  end
  else
    Result := AskToCloseApp('продолжить установку');
end;

function InitializeUninstall: Boolean;
begin
  if UninstallSilent then
    Result := WaitForAppExit(15000)
  else
    Result := AskToCloseApp('продолжить удаление');
end;
