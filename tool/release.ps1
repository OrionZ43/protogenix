# tool/release.ps1
#
# Сборка и публикация релиза Protogenix на GitHub.
#
#   powershell -ExecutionPolicy Bypass -File tool/release.ps1 -NotesFile docs/release-notes/v1.0.0.md
#       собрать всё и подготовить файлы в build/release/vX.Y.Z/ — без публикации
#   powershell -ExecutionPolicy Bypass -File tool/release.ps1 -NotesFile docs/release-notes/v1.0.0.md -Publish
#       то же самое + GitHub Release vX.Y.Z со всеми файлами
#   powershell -ExecutionPolicy Bypass -File tool/release.ps1 -Bump patch -NotesFile docs/release-notes/v1.0.1.md -Publish
#       поднять версию (patch, minor или major) и сразу выпустить: после
#       успешной сборки — коммит «release: vX.Y.Z» (pubspec.yaml и описание),
#       git push и GitHub Release
#
# Что делает:
#   1. Проверки: версия X.Y.Z+N из pubspec.yaml (с -Bump — следующая, а N на
#      единицу больше опубликованного); описание лежит в vX.Y.Z.md; нет
#      незакоммиченных изменений (с -Bump — кроме файла описания); N больше,
#      чем у последнего опубликованного релиза; для -Publish — тега vX.Y.Z ещё
#      нет и коммит уже запушен на GitHub.
#   2. Android: APK под arm64-v8a и armeabi-v7a (по одной архитектуре через
#      --target-platform; .so плагинов отсекает abiFilters в build.gradle.kts)
#      и universal. Каждый APK проверяется: подписан release-ключом (SHA-256
#      сертификата ниже), versionCode = N, в нём ровно нужные архитектуры и
#      у каждой есть движок Flutter и код приложения, выровнен под 16 КБ
#      страницы. --split-per-abi не используется: Flutter тогда меняет versionCode
#      на «код ABI × 1000 + N», и приложение перестаёт видеть обновления.
#   3. Windows: приложение и установщик Inno Setup (tool/build_windows_installer.ps1).
#   4. manifest.json с размерами и SHA-256 → подпись → protogenix-update.json.
#      С -Bump — коммит новой версии; если что-то упало раньше, pubspec.yaml
#      возвращается как был.
#   5. С -Publish: (с -Bump — git push) gh release create и проверка, что
#      GitHub отдаёт новый манифест.
#
# Нужно: Flutter, Android SDK, Inno Setup 6, gh (winget install GitHub.cli;
# gh auth login), android/key.properties с release-ключом, ключ подписи
# манифеста. Правила — .claude/rules/release.md.

param(
    [Parameter(Mandatory = $true)] [string]$NotesFile,
    [int]$MinSupportedBuild = 1,
    [string]$UpdateKeyPath = (Join-Path $env:USERPROFILE '.protogenix\update-signing.key'),
    [string]$UpdateKeyId = 'z43-2026',
    [ValidateSet('patch', 'minor', 'major')] [string]$Bump,
    [switch]$Publish,
    [switch]$AllowDirty
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$Repo = 'OrionZ43/protogenix'
$ManifestUrl = "https://github.com/$Repo/releases/latest/download/protogenix-update.json"

# SHA-256 сертификата release-ключа Android (публичное значение, см. release.md).
$ExpectedCertSha256 = '61502f44ef266bb7c27b5671757ca6c752a6d690d2f0d2c940a32bbdc419b0f8'

$root = Split-Path -Parent $PSScriptRoot
$NotesFile = (Resolve-Path $NotesFile).Path
$UpdateKeyPath = [System.IO.Path]::GetFullPath($UpdateKeyPath)

function Step([string]$text) { Write-Host "`n=== $text" -ForegroundColor Cyan }

# Нативная команда с проверкой кода выхода. Без перенаправлений: в Windows
# PowerShell 5.1 при ErrorActionPreference=Stop перенаправленный stderr
# превращается в прерывающую ошибку.
function Invoke-Checked([string]$what, [scriptblock]$command) {
    & $command
    if ($LASTEXITCODE -ne 0) { throw "$what завершилось с кодом $LASTEXITCODE" }
}

# Нативная команда, у которой нужен вывод или код выхода, а stderr не важен.
function Invoke-Native([scriptblock]$command) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $command 2>&1 | Out-String } finally { $ErrorActionPreference = $previous }
}

function Get-SdkTool([string]$name) {
    $props = Get-Content (Join-Path $root 'android\local.properties') -Raw
    if ($props -notmatch 'sdk\.dir=(.+)') { throw 'В android/local.properties нет sdk.dir' }
    $sdk = $Matches[1].Trim() -replace '\\:', ':' -replace '\\\\', '\'
    $tool = Get-ChildItem (Join-Path $sdk 'build-tools') -Directory |
        Sort-Object Name -Descending |
        ForEach-Object { Join-Path $_.FullName $name } |
        Where-Object { Test-Path $_ } |
        Select-Object -First 1
    if (-not $tool) { throw "Не найден $name в Android SDK ($sdk)" }
    return $tool
}

function Assert-ReleaseApk([string]$apk, [int]$expectedVersionCode, [string[]]$expectedAbis) {
    $certs = Invoke-Native { & $script:apksigner verify --print-certs $apk }
    if ($LASTEXITCODE -ne 0) { throw "apksigner не принял $apk`n$certs" }
    if ($certs -notmatch 'Signer #1 certificate SHA-256 digest: ([0-9a-f]+)') { throw "Не удалось прочитать подпись $apk" }
    if ($Matches[1] -ne $ExpectedCertSha256) {
        throw "$apk подписан не release-ключом (SHA-256 $($Matches[1])). Проверь android/key.properties."
    }

    $badging = Invoke-Native { & $script:aapt2 dump badging $apk }
    if ($badging -notmatch "versionCode='(\d+)'") { throw "Не удалось прочитать versionCode $apk" }
    if ([int]$Matches[1] -ne $expectedVersionCode) {
        throw "$apk`: versionCode $($Matches[1]), а должен быть $expectedVersionCode"
    }

    # Каждая архитектура в APK должна быть полной — с движком Flutter и кодом
    # приложения. Иначе телефон с этой архитектурой поставит APK и не запустит его.
    $zip = [System.IO.Compression.ZipFile]::OpenRead($apk)
    try { $libs = @($zip.Entries | ForEach-Object { $_.FullName } | Where-Object { $_ -like 'lib/*' }) } finally { $zip.Dispose() }
    $abis = @($libs | ForEach-Object { ($_ -split '/')[1] } | Sort-Object -Unique)
    $expected = @($expectedAbis | Sort-Object)
    if (($abis -join ', ') -ne ($expected -join ', ')) {
        throw "$apk`: архитектуры $($abis -join ', '), а должны быть $($expected -join ', ')"
    }
    foreach ($abi in $abis) {
        foreach ($lib in 'libflutter.so', 'libapp.so') {
            if ($libs -notcontains "lib/$abi/$lib") { throw "$apk`: нет lib/$abi/$lib" }
        }
    }

    $aligned = Invoke-Native { & $script:zipalign -c -P 16 4 $apk }
    if ($LASTEXITCODE -ne 0) { throw "$apk не выровнен под 16 КБ страницы памяти`n$aligned" }
}

# build последнего опубликованного релиза; 0 — релизов ещё нет.
function Get-PublishedBuild {
    try {
        $response = Invoke-WebRequest -Uri $ManifestUrl -UseBasicParsing
    } catch {
        $status = $_.Exception.Response.StatusCode.value__
        if ($status -eq 404) { return 0 }
        throw "Не удалось получить опубликованный манифест: $($_.Exception.Message)"
    }
    $content = $response.Content
    if ($content -is [byte[]]) { $content = [System.Text.Encoding]::UTF8.GetString($content) }
    $envelope = $content | ConvertFrom-Json
    $payload = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($envelope.payload))
    return [int](($payload | ConvertFrom-Json).build)
}

$pubspecBackup = $null
Push-Location $root
try {
    # ── 1. Проверки ──────────────────────────────────────────────────────────
    Step 'Проверки'

    $versionMatch = Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$'
    if (-not $versionMatch) { throw 'Не нашёл строку version: X.Y.Z+N в pubspec.yaml' }
    $version = $versionMatch.Matches[0].Groups[1].Value
    $build = [int]$versionMatch.Matches[0].Groups[2].Value
    if ($Bump -and $AllowDirty) { throw '-Bump и -AllowDirty вместе нельзя: новая версия коммитится, а коммит делается только с чистого дерева' }

    $notes = (Get-Content -Raw -Encoding UTF8 $NotesFile).Trim()
    if (-not $notes) { throw "Файл с описанием релиза пуст: $NotesFile" }
    # На GitHub описание уходит целиком, как есть. В приложение (баннер «Что
    # нового»: простой текст, первые 500 символов) — только часть до строки
    # <!-- more -->, если она есть, без разметки markdown и HTML, «•» вместо «- ».
    $appNotes = ($notes -split '<!--\s*more\s*-->', 2)[0]
    $appNotes = $appNotes -replace '(?s)<!--.*?-->', '' -replace '<[^>]+>', '' `
        -replace '!\[[^\]]*\]\([^)]*\)', '' -replace '\[([^\]]+)\]\([^)]*\)', '$1'
    $plainNotes = ((($appNotes -split "`r?`n" | ForEach-Object {
        $_ -replace '^\s*#+\s*', '' -replace '^(\s*)[-*]\s+', '$1• ' -replace '\*\*|__|`', ''
    }) -join "`n") -replace '(\n[ \t]*){3,}', "`n`n").Trim()
    if (-not $plainNotes) { throw "В описании нет текста для приложения (до <!-- more -->): $NotesFile" }
    if ($plainNotes.Length -gt 500) {
        Write-Warning "Текст для приложения — $($plainNotes.Length) символов, баннер покажет только первые 500. Сократи часть до <!-- more -->."
    }

    if (-not (Test-Path $UpdateKeyPath)) { throw "Нет ключа подписи манифеста: $UpdateKeyPath" }

    # Изменённые файлы во всём репозитории плюс новые файлы там, откуда берётся
    # сборка: иначе забытый `git add` не заметить — локально всё соберётся,
    # а в коммите релиза файла не будет.
    $dirty = @(git status --porcelain --untracked-files=no) +
        @(git ls-files --others --exclude-standard -- lib android windows assets tool pubspec.yaml pubspec.lock | ForEach-Object { "?? $_" })
    # С -Bump описание релиза коммитится вместе с новой версией — его правки
    # не мешают. Путь относительно репозитория спрашиваем у git: сравнение
    # строк ломается, если одна из них с коротким именем папки (8.3).
    $notesRel = $null
    $notesDir = Split-Path -Parent $NotesFile
    $notesTop = Invoke-Native { git -C $notesDir rev-parse --show-toplevel }
    if ($LASTEXITCODE -eq 0 -and $notesTop.Trim() -eq (Invoke-Native { git rev-parse --show-toplevel }).Trim()) {
        $notesRel = (Invoke-Native { git -C $notesDir rev-parse --show-prefix }).Trim() + (Split-Path -Leaf $NotesFile)
    }
    if ($Bump -and $notesRel) { $dirty = @($dirty | Where-Object { $_.Substring(3) -ne $notesRel }) }
    if ($dirty.Count -gt 0) {
        $list = $dirty -join "`n"
        if (-not $AllowDirty) { throw "Есть незакоммиченные изменения — релиз собирается только из закоммиченного кода:`n$list" }
        Write-Warning "Сборка из незакоммиченного кода (-AllowDirty):`n$list"
    }

    $publishedBuild = Get-PublishedBuild
    Write-Host "Опубликованная сборка: $publishedBuild"

    if ($Bump) {
        $current = "$version+$build"
        $parts = [int[]]$version.Split('.')
        switch ($Bump) {
            'major' { $parts = @(($parts[0] + 1), 0, 0) }
            'minor' { $parts = @($parts[0], ($parts[1] + 1), 0) }
            'patch' { $parts = @($parts[0], $parts[1], ($parts[2] + 1)) }
        }
        $version = $parts -join '.'
        $build = [Math]::Max($build, $publishedBuild) + 1
        Write-Host "Новая версия: $current → $version+$build"
    }
    $tag = "v$version"
    Write-Host "Версия $version, сборка $build, тег $tag"

    if ([System.IO.Path]::GetFileNameWithoutExtension($NotesFile) -ne $tag) {
        throw "Описание релиза $tag должно лежать в файле $tag.md, а передан $(Split-Path -Leaf $NotesFile)"
    }
    if ($MinSupportedBuild -lt 0 -or $MinSupportedBuild -gt $build) {
        throw "MinSupportedBuild должен быть от 0 до $build"
    }
    if ($build -le $publishedBuild) {
        throw "Сборка $build не новее опубликованной ($publishedBuild) — подними +N в pubspec.yaml"
    }

    if ($Publish) {
        if ($AllowDirty) { throw '-Publish и -AllowDirty вместе нельзя: публикуется только закоммиченный код' }
        if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
            throw 'Нет GitHub CLI: winget install GitHub.cli, затем gh auth login'
        }
        $auth = Invoke-Native { gh auth status }
        if ($LASTEXITCODE -ne 0) { throw "gh не авторизован — выполни gh auth login`n$auth" }
        Invoke-Native { gh release view $tag --repo $Repo } | Out-Null
        if ($LASTEXITCODE -eq 0) { throw "Релиз $tag уже существует" }
        Invoke-Checked 'git fetch' { git fetch origin --quiet }
        Invoke-Native { git merge-base --is-ancestor HEAD origin/master } | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Текущий коммит не запушен в origin/master — сначала git push' }
    }

    $script:apksigner = Get-SdkTool 'apksigner.bat'
    $script:aapt2 = Get-SdkTool 'aapt2.exe'
    $script:zipalign = Get-SdkTool 'zipalign.exe'

    $outDir = Join-Path $root "build\release\$tag"
    if (Test-Path $outDir) { Remove-Item $outDir -Recurse -Force }
    New-Item -ItemType Directory $outDir | Out-Null

    # Новая версия попадает в pubspec.yaml до сборки, а коммитится только
    # после неё: если что-то упадёт раньше, finally вернёт прежний файл.
    if ($Bump) {
        $pubspecPath = Join-Path $root 'pubspec.yaml'
        $pubspecBackup = [System.IO.File]::ReadAllBytes($pubspecPath)
        $bumped = ([regex]'(?m)^version:[^\r\n]*').Replace([System.IO.File]::ReadAllText($pubspecPath), "version: $version+$build", 1)
        [System.IO.File]::WriteAllText($pubspecPath, $bumped, (New-Object System.Text.UTF8Encoding $false))
    }

    # ── 2. Android ───────────────────────────────────────────────────────────
    $apkOut = Join-Path $root 'build\app\outputs\flutter-apk\app-release.apk'
    $androidBuilds = [ordered]@{
        'android-arm64-v8a'   = @{ Platform = 'android-arm64'; Abis = @('arm64-v8a') }
        'android-armeabi-v7a' = @{ Platform = 'android-arm'; Abis = @('armeabi-v7a') }
        'android-universal'   = @{ Platform = $null; Abis = @('arm64-v8a', 'armeabi-v7a', 'x86_64') }
    }
    $assetFiles = [ordered]@{}
    foreach ($key in $androidBuilds.Keys) {
        Step "Android: $key"
        $spec = $androidBuilds[$key]
        if ($spec.Platform) {
            Invoke-Checked "flutter build apk ($key)" { flutter build apk --release --target-platform $spec.Platform }
        } else {
            Invoke-Checked "flutter build apk ($key)" { flutter build apk --release }
        }
        $target = Join-Path $outDir "protogenix-$key.apk"
        Copy-Item $apkOut $target -Force
        Assert-ReleaseApk $target $build $spec.Abis
        $assetFiles[$key] = $target
    }

    # ── 3. Windows ───────────────────────────────────────────────────────────
    Step 'Windows: приложение и установщик'
    Invoke-Checked 'build_windows_installer.ps1' {
        powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tool\build_windows_installer.ps1')
    }
    # Номер сборки exe должен совпасть с build манифеста: иначе после обновления
    # приложение снова увидит «новую» версию, и получится петля. Особенно важно
    # после тестовых сборок с --build-number.
    $exeVersion = (Get-Item (Join-Path $root 'build\windows\x64\runner\Release\protogenix.exe')).VersionInfo.ProductVersion
    if ($exeVersion -ne "$version+$build") {
        throw "protogenix.exe собран как $exeVersion, а должен быть $version+$build. Выполни flutter clean и запусти скрипт снова."
    }
    # В релизе имена файлов без версии: ссылка releases/latest/download/<имя>
    # тогда всегда ведёт на свежий релиз (ей пользуется сайт Z43 Studios).
    # Версия есть в теге и в манифесте. Подробнее — release.md.
    $setup = Join-Path $outDir 'Protogenix-Setup.exe'
    Copy-Item (Join-Path $root "build\installer\Protogenix-Setup-$version.exe") $setup -Force
    $assetFiles['windows-x64'] = $setup

    # ── 4. Манифест и подпись ────────────────────────────────────────────────
    Step 'Манифест'
    $assets = [ordered]@{}
    foreach ($key in $assetFiles.Keys) {
        $file = Get-Item $assetFiles[$key]
        $assets[$key] = [ordered]@{
            urls   = @("https://github.com/$Repo/releases/download/$tag/$($file.Name)")
            size   = $file.Length
            sha256 = (Get-FileHash $file.FullName -Algorithm SHA256).Hash.ToLower()
        }
    }
    $manifest = [ordered]@{
        version           = $version
        build             = $build
        minSupportedBuild = $MinSupportedBuild
        publishedAt       = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        notes             = $plainNotes
        releaseUrl        = "https://github.com/$Repo/releases/tag/$tag"
        assets            = $assets
    }
    $manifestPath = Join-Path $outDir 'manifest.json'
    $envelopePath = Join-Path $outDir 'protogenix-update.json'
    [System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding $false))
    Invoke-Checked 'Подпись манифеста' {
        dart run tool/update_signing.dart sign $UpdateKeyId $UpdateKeyPath $manifestPath $envelopePath
    }

    Step 'Готово'
    Get-ChildItem $outDir -File | ForEach-Object { '{0,-48} {1,10:N1} MB' -f $_.Name, ($_.Length / 1MB) }

    if ($Bump) {
        Step "Коммит версии $version+$build"
        $commitPaths = @('pubspec.yaml')
        if ($notesRel) { $commitPaths += $notesRel }
        Invoke-Checked 'git add' { git add -- @commitPaths }
        Invoke-Checked 'git commit' { git commit --quiet -m "release: $tag" -- @commitPaths }
        $pubspecBackup = $null
    }

    # ── 5. Публикация ────────────────────────────────────────────────────────
    if (-not $Publish) {
        if ($Bump) {
            Write-Host "`nВерсия $version+$build закоммичена локально, файлы в $outDir. Проверь их, сделай git push и запусти скрипт с -Publish, но уже без -Bump."
        } else {
            Write-Host "`nФайлы в $outDir. Проверь их и запусти с -Publish, чтобы опубликовать."
        }
        return
    }

    Step "Публикация $tag"
    if ($Bump) {
        # Коммит версии лежит поверх уже запушенного (проверено в начале). Если
        # за время сборки в master что-то слили, push не пройдёт и релиз не
        # создастся.
        git push origin HEAD:master
        if ($LASTEXITCODE -ne 0) {
            throw "git push не прошёл. Версия $version+$build закоммичена локально: git pull --rebase, затем скрипт с -Publish без -Bump."
        }
    }
    $uploads = @($assetFiles.Values) + $envelopePath
    $commit = git rev-parse HEAD
    Invoke-Checked 'gh release create' {
        gh release create $tag @uploads --repo $Repo --target $commit --title "Protogenix $version" --notes-file $NotesFile --latest
    }

    $downloaded = Join-Path $env:TEMP 'protogenix-update-check.json'
    Invoke-WebRequest -Uri $ManifestUrl -OutFile $downloaded -UseBasicParsing
    $remoteHash = (Get-FileHash $downloaded -Algorithm SHA256).Hash
    $localHash = (Get-FileHash $envelopePath -Algorithm SHA256).Hash
    Remove-Item $downloaded -Force
    if ($remoteHash -ne $localHash) { throw 'GitHub отдаёт не тот protogenix-update.json — проверь релиз вручную' }
    Write-Host "Опубликовано: https://github.com/$Repo/releases/tag/$tag"
}
finally {
    if ($pubspecBackup) {
        [System.IO.File]::WriteAllBytes((Join-Path $root 'pubspec.yaml'), $pubspecBackup)
        Write-Warning 'Релиз не собран — pubspec.yaml возвращён к прежней версии'
    }
    Pop-Location
}
