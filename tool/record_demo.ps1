# tool/record_demo.ps1
#
# Запись демо-видео для сайта: окно Protogenix с караоке и звук трека.
#
#   powershell -ExecutionPolicy Bypass -File tool/record_demo.ps1 -TrackId 92pwZ8zUGbE -AudioFile <аудио трека> -From 63 -To 90
#
# Что делает:
#   1. Собирает Windows-версию в режиме демо (lib/app/demo_mode.dart): трек сам
#      включается за LeadIn секунд до From, развёрнутый плеер открывается сам.
#      -SkipBuild — взять уже собранную (с теми же TrackId, From и LeadIn).
#   2. Запускает её и пишет окно через ffmpeg (Windows Graphics Capture: только
#      само окно, без курсора, даже если его что-то перекрывает) с метками
#      времени по часам.
#   3. Сводит видео со звуком. Приложение пишет пары «время на часах — позиция
#      трека» (%TEMP%\protogenix_demo_sync.csv), по ним находится кадр, где
#      играет From. Звук берётся из файла трека, а не с колонок, — он чище и
#      совпадает с тем, что показывает караоке.
#   4. Кодирует MP4 (H.264 + AAC, faststart) и кадр-обложку PNG.
#
# Установленный Protogenix нужно закрыть: второй экземпляр приложение не
# запускает. Во время записи трек играет вслух. Нужен ffmpeg с gfxcapture
# (8.0+). Сохранено в UTF-8 с BOM, как все .ps1 в tool/.

param(
    [Parameter(Mandatory = $true)] [string]$TrackId,
    [Parameter(Mandatory = $true)] [string]$AudioFile,
    [Parameter(Mandatory = $true)] [double]$From,
    [Parameter(Mandatory = $true)] [double]$To,
    [double]$LeadIn = 3,
    [string]$OutDir = 'build\demo',
    [int]$Fps = 30,
    [int]$MaxWidth = 1280,
    # Своя полоса заголовка окна (WindowTitleBar) при масштабе 100 %
    [int]$CropTop = 32,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$inv = [Globalization.CultureInfo]::InvariantCulture
$root = Split-Path -Parent $PSScriptRoot
$AudioFile = (Resolve-Path $AudioFile).Path
if ($To -le $From) { throw 'To должен быть больше From' }
$duration = $To - $From
$startMs = [int][Math]::Round(($From - $LeadIn) * 1000)
if ($startMs -lt 0) { throw 'LeadIn больше From' }

function Step([string]$text) { Write-Host "`n=== $text" -ForegroundColor Cyan }
function Num([double]$value) { $value.ToString('0.000', $inv) }

# Нативная команда, у которой нужен код выхода; stderr пишется в файл.
function Invoke-Ffmpeg([string]$arguments, [string]$logFile) {
    $p = Start-Process ffmpeg -ArgumentList $arguments -NoNewWindow -Wait -PassThru -RedirectStandardError $logFile
    if ($p.ExitCode -ne 0) { throw "ffmpeg завершился с кодом $($p.ExitCode), лог: $logFile" }
}

if (Get-Process protogenix -ErrorAction SilentlyContinue) {
    throw 'Protogenix запущен — закрой его: второй экземпляр приложение не запускает'
}

Push-Location $root
try {
    $out = (New-Item -ItemType Directory -Force $OutDir).FullName
    $raw = Join-Path $out 'raw.mkv'
    $sync = Join-Path ([IO.Path]::GetTempPath()) 'protogenix_demo_sync.csv'
    if (Test-Path $sync) { Remove-Item $sync }

    if (-not $SkipBuild) {
        Step 'Сборка в режиме демо'
        flutter build windows --release "--dart-define=PROTOGENIX_DEMO_TRACK=$TrackId" "--dart-define=PROTOGENIX_DEMO_START_MS=$startMs"
        if ($LASTEXITCODE -ne 0) { throw "flutter build завершилось с кодом $LASTEXITCODE" }
    }
    $exe = Join-Path $root 'build\windows\x64\runner\Release\protogenix.exe'

    Step 'Запись'
    $app = Start-Process $exe -PassThru
    try {
        # gfxcapture не стартует без окна — ждём его
        $deadline = (Get-Date).AddSeconds(30)
        do {
            Start-Sleep -Milliseconds 200
            $app.Refresh()
        } while ($app.MainWindowHandle -eq 0 -and (Get-Date) -lt $deadline)
        if ($app.MainWindowHandle -eq 0) { throw 'Окно Protogenix так и не появилось' }

        $captureSec = [int][Math]::Ceiling($LeadIn + $duration + 6)
        Invoke-Ffmpeg ('-hide_banner -y -use_wallclock_as_timestamps 1 -f lavfi ' +
            '-i "gfxcapture=window_title=^Protogenix$:capture_cursor=0:max_framerate=60,hwdownload,format=bgra" ' +
            "-t $captureSec -c:v libx264 -preset ultrafast -crf 12 -pix_fmt yuv444p `"$raw`"") (Join-Path $out 'capture.log')
    } finally {
        if (-not $app.HasExited) {
            $null = $app.CloseMainWindow()
            if (-not $app.WaitForExit(5000)) { Stop-Process -Id $app.Id -Force }
        }
    }

    Step 'Сведение'
    # С -use_wallclock_as_timestamps ffmpeg печатает время первого кадра по часам
    $startLine = Select-String -Path (Join-Path $out 'capture.log') -Pattern 'start: ([0-9.]+)' | Select-Object -First 1
    if (-not $startLine) { throw 'В логе записи нет времени первого кадра' }
    $videoStartUs = [double]::Parse($startLine.Matches[0].Groups[1].Value, $inv) * 1e6

    if (-not (Test-Path $sync)) { throw "Нет $sync — приложение не включило трек (есть ли $TrackId в медиатеке?)" }
    $offsets = @(Get-Content $sync | ForEach-Object {
        $wall, $pos = $_ -split ','
        [double]::Parse($wall, $inv) - [double]::Parse($pos, $inv)
    } | Sort-Object)
    if ($offsets.Count -lt 10) { throw "Мало точек синхронизации: $($offsets.Count)" }
    # Смещение «часы − позиция» постоянно, пока трек играет; медиана убирает
    # выбросы вокруг перемотки и старта.
    $offsetUs = $offsets[[int]($offsets.Count / 2)]
    $spreadMs = ($offsets[[int]($offsets.Count * 0.9)] - $offsets[[int]($offsets.Count * 0.1)]) / 1000
    $videoAt = ($From * 1e6 + $offsetUs - $videoStartUs) / 1e6
    Write-Host "Позиция $(Num $From) с — на $(Num $videoAt) с записи; разброс точек $([int]$spreadMs) мс"
    if ($videoAt -lt 0) { throw 'Запись началась позже нужного места — увеличь LeadIn' }
    if ($spreadMs -gt 80) { Write-Warning 'Большой разброс точек синхронизации — проверь звук на глаз' }

    $mp4 = Join-Path $out "protogenix-demo.mp4"
    $vf = "crop=iw:ih-$($CropTop):0:$($CropTop),fps=$Fps,scale='min($MaxWidth,iw)':-2:flags=lanczos,format=yuv420p"
    # Короткие затухания — чтобы на повторе не щёлкало
    $af = "afade=t=in:d=0.25,afade=t=out:st=$(Num ($duration - 0.6)):d=0.6"
    Invoke-Ffmpeg ("-hide_banner -y -ss $(Num $videoAt) -i `"$raw`" -ss $(Num $From) -i `"$AudioFile`" " +
        "-t $(Num $duration) -map 0:v:0 -map 1:a:0 -vf `"$vf`" -af `"$af`" " +
        "-c:v libx264 -preset slow -crf 23 -profile:v high -c:a aac -b:a 128k -movflags +faststart `"$mp4`"") (Join-Path $out 'encode.log')

    $poster = Join-Path $out 'protogenix-demo-poster.png'
    Invoke-Ffmpeg ("-hide_banner -y -ss 1 -i `"$mp4`" -frames:v 1 `"$poster`"") (Join-Path $out 'poster.log')

    Step 'Готово'
    Get-ChildItem $mp4, $poster | ForEach-Object { '{0,-32} {1,8:N1} МБ' -f $_.Name, ($_.Length / 1MB) }
}
finally {
    Pop-Location
}
