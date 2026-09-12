# tool/youtube_health_check.ps1
#
# Ежедневная проверка «скачивание с YouTube ещё работает» на машине Orion.
# Сама проверка — tool/youtube_health_check.dart; этот скрипт запускает её,
# ведёт лог и показывает уведомление Windows, если что-то сломалось.
#
#   powershell -ExecutionPolicy Bypass -File tool/youtube_health_check.ps1
#       проверить сейчас
#   powershell -ExecutionPolicy Bypass -File tool/youtube_health_check.ps1 -Install
#       задание в Планировщике: каждый день в 12:00 (-At ЧЧ:ММ — другое время),
#       а если ПК в это время был выключен — при первой возможности
#   powershell -ExecutionPolicy Bypass -File tool/youtube_health_check.ps1 -Uninstall
#       убрать задание
#   powershell -ExecutionPolicy Bypass -File tool/youtube_health_check.ps1 -TestNotification
#       показать тестовое уведомление
#
# Уведомление — если первый клиент не справился, что-то не качается или
# проверка не запустилась. Нет сети — только запись в лог:
# %LOCALAPPDATA%\Z43 Studios\health\youtube.log. Задание ссылается на этот
# файл: если перенести репозиторий, запустить -Install заново.

param(
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$TestNotification,
    [string]$At = '12:00'
)

$TaskName = 'Protogenix YouTube check'
$root = Split-Path -Parent $PSScriptRoot
$logPath = Join-Path $env:LOCALAPPDATA 'Z43 Studios\health\youtube.log'
$utf8 = New-Object System.Text.UTF8Encoding $false

function Show-Notification([string]$title, [string]$text) {
    try {
        $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        $null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
        $escape = [System.Security.SecurityElement]
        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xml.LoadXml("<toast><visual><binding template='ToastGeneric'><text>$($escape::Escape($title))</text><text>$($escape::Escape($text))</text></binding></visual></toast>")
        # Своего AppUserModelID у скрипта нет — берём AUMID самого Windows PowerShell
        $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show([Windows.UI.Notifications.ToastNotification]::new($xml))
    } catch {
        # Запасной путь — окно сообщения; msg не ждёт, пока его закроют
        msg.exe $env:USERNAME "$title`n$text"
    }
}

# Последний блок лога (после последней строки «=== …»)
function Get-LastReport {
    $lines = @(Get-Content -Encoding UTF8 $logPath)
    $start = 0
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        if ($lines[$i].StartsWith('=== ')) { $start = $i; break }
    }
    return ($lines[$start..($lines.Count - 1)] -join "`n")
}

if ($Install) {
    $actionArgs = @{
        Execute          = 'powershell.exe'
        Argument         = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`""
        WorkingDirectory = $root
    }
    $settingsArgs = @{
        StartWhenAvailable         = $true
        RunOnlyIfNetworkAvailable  = $true
        AllowStartIfOnBatteries    = $true
        DontStopIfGoingOnBatteries = $true
        ExecutionTimeLimit         = New-TimeSpan -Minutes 15
    }
    $task = @{
        TaskName    = $TaskName
        Description = 'Проверяет, качается ли ещё YouTube (tool/youtube_health_check.ps1 в репозитории Protogenix)'
        Action      = New-ScheduledTaskAction @actionArgs
        Trigger     = New-ScheduledTaskTrigger -Daily -At $At
        Settings    = New-ScheduledTaskSettingsSet @settingsArgs
        Principal   = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
    }
    Register-ScheduledTask @task -Force | Out-Null
    Write-Host "Задание «$TaskName»: каждый день в $At. Лог: $logPath"
    return
}

if ($Uninstall) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Задание «$TaskName» удалено"
    return
}

if ($TestNotification) {
    Show-Notification 'Protogenix: проверка YouTube' 'Тестовое уведомление: так будет выглядеть сообщение о поломке.'
    return
}

New-Item -ItemType Directory -Force (Split-Path -Parent $logPath) | Out-Null
if ((Test-Path $logPath) -and (Get-Item $logPath).Length -gt 1MB) {
    $tail = @(Get-Content -Encoding UTF8 $logPath | Select-Object -Last 2000)
    [System.IO.File]::WriteAllLines($logPath, $tail, $utf8)
}

Push-Location $root
try {
    # Отчёт Dart пишет в лог сам (UTF-8); вывод нужен только на случай падения
    $output = & dart run tool/youtube_health_check.dart --log $logPath 2>&1 | Out-String
    $code = $LASTEXITCODE
} catch {
    $output = $_.Exception.Message
    $code = -1
} finally {
    Pop-Location
}

switch ($code) {
    0 { Write-Host (Get-LastReport) }
    3 { Write-Host (Get-LastReport) }
    1 {
        $report = Get-LastReport
        Write-Host $report
        Show-Notification 'Protogenix: YouTube — visionOS не справился' "$report`nЛог: $logPath"
    }
    2 {
        $report = Get-LastReport
        Write-Host $report
        Show-Notification 'Protogenix: скачивание с YouTube сломалось' "$report`nЛог: $logPath"
    }
    default {
        [System.IO.File]::AppendAllText($logPath, "=== $(Get-Date -Format 'yyyy-MM-dd HH:mm') · проверка не запустилась (код $code)`n$output`n", $utf8)
        Write-Host "Проверка не запустилась (код $code):`n$output"
        Show-Notification 'Protogenix: проверка YouTube не запустилась' "Код $code. Подробности в логе: $logPath"
    }
}
exit $(if ($code -lt 0) { 255 } else { $code })
