# tool/build_windows_installer.ps1
#
# Собирает Windows-релиз и установщик Inno Setup.
#
#   powershell -ExecutionPolicy Bypass -File tool/build_windows_installer.ps1
#   powershell -ExecutionPolicy Bypass -File tool/build_windows_installer.ps1 -SkipFlutterBuild
#
# Версия берётся из pubspec.yaml (X.Y.Z из `version: X.Y.Z+N`).
# Результат: build/installer/Protogenix-Setup-X.Y.Z.exe
# Нужен Inno Setup 6: winget install JRSoftware.InnoSetup

param([switch]$SkipFlutterBuild)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

$match = Select-String -Path (Join-Path $root 'pubspec.yaml') -Pattern '^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$'
if (-not $match) { throw 'Не нашёл строку version: X.Y.Z+N в pubspec.yaml' }
$version = $match.Matches[0].Groups[1].Value

$iscc = @(
    (Get-Command iscc -ErrorAction SilentlyContinue).Source,
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $iscc) { throw 'Не найден Inno Setup 6 (ISCC.exe). Установи: winget install JRSoftware.InnoSetup' }

Push-Location $root
try {
    if (-not $SkipFlutterBuild) {
        flutter build windows --release
        if ($LASTEXITCODE -ne 0) { throw "flutter build windows завершился с кодом $LASTEXITCODE" }
    }

    $source = Join-Path $root 'build\windows\x64\runner\Release'
    if (-not (Test-Path (Join-Path $source 'protogenix.exe'))) { throw "Нет собранного приложения в $source" }

    $output = Join-Path $root 'build\installer'
    & $iscc "/DAppVersion=$version" "/DSourceDir=$source" "/DOutputDir=$output" (Join-Path $root 'windows\installer\protogenix.iss')
    if ($LASTEXITCODE -ne 0) { throw "ISCC завершился с кодом $LASTEXITCODE" }

    $setup = Join-Path $output "Protogenix-Setup-$version.exe"
    $hash = (Get-FileHash $setup -Algorithm SHA256).Hash.ToLower()
    Write-Host "Готово: $setup"
    Write-Host ("Размер: {0} байт, SHA-256: {1}" -f (Get-Item $setup).Length, $hash)
}
finally {
    Pop-Location
}
