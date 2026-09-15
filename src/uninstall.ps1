$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Show-Failure {
    param([string]$Message)

    Write-Host ""
    Write-Host "[FAIL] $Message" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

try {
    $InstallRoot = Join-Path $env:LOCALAPPDATA "PCManagerKoPatch"
    $ConfigKey = "HKCU:\Software\PCManagerKoPatch"
    $RunKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    $WebViewKey = "HKCU:\Software\Policies\Microsoft\Edge\WebView2\AdditionalBrowserArguments"

    $StartupDirectory = [Environment]::GetFolderPath("Startup")
    $StartupLauncher = Join-Path $StartupDirectory "PCManagerKoPatch.vbs"

    Write-Host ""
    Write-Host "Removing PC Manager Korean Translation Patch..." -ForegroundColor Cyan
    Write-Host ""

    try {
        $AgentPid = (Get-ItemProperty -LiteralPath $ConfigKey -Name "AgentPid" -ErrorAction SilentlyContinue).AgentPid

        if ($AgentPid) {
            $AgentProcess = Get-Process -Id $AgentPid -ErrorAction SilentlyContinue

            if ($AgentProcess -and $AgentProcess.ProcessName -ieq "powershell") {
                Stop-Process -Id $AgentPid -Force -ErrorAction SilentlyContinue
            }
        }
    }
    catch {}

    Remove-ItemProperty -Path $RunKey -Name "PCManagerKoPatch" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $RunKey -Name "PCManagerKoPatchAgent" -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $StartupLauncher -Force -ErrorAction SilentlyContinue

    # Restore the app-specific WebView2 arguments that existed before installation.
    $HadPreviousArguments = $false
    $PreviousArguments = ""

    try {
        $HadPreviousArguments = [bool](Get-ItemProperty `
            -LiteralPath $ConfigKey `
            -Name "HadPreviousBrowserArguments" `
            -ErrorAction Stop).HadPreviousBrowserArguments
    }
    catch {}

    try {
        $PreviousArguments = [string](Get-ItemProperty `
            -LiteralPath $ConfigKey `
            -Name "PreviousBrowserArguments" `
            -ErrorAction Stop).PreviousBrowserArguments
    }
    catch {}

    if ($HadPreviousArguments) {
        New-Item -Path $WebViewKey -Force | Out-Null
        New-ItemProperty `
            -Path $WebViewKey `
            -Name "MSPCManager.exe" `
            -PropertyType String `
            -Value $PreviousArguments `
            -Force | Out-Null
    }
    else {
        Remove-ItemProperty `
            -Path $WebViewKey `
            -Name "MSPCManager.exe" `
            -ErrorAction SilentlyContinue
    }

    Remove-Item -Path $ConfigKey -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $InstallRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:LOCALAPPDATA\PCManagerKoPatch.ps1" -Force -ErrorAction SilentlyContinue

    Stop-Process -Name "MSPCManager" -Force -ErrorAction SilentlyContinue
    Stop-Process -Name "MSPCManagerCore" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 700

    $App = Get-AppxPackage Microsoft.MicrosoftPCManager -ErrorAction SilentlyContinue

    if ($App) {
        $PcManagerExe = Join-Path $App.InstallLocation "PCManager\MSPCManager.exe"

        if (Test-Path $PcManagerExe) {
            Start-Process $PcManagerExe
        }
    }

    Write-Host "REMOVAL COMPLETE" -ForegroundColor Green
    Write-Host ""
    exit 0
}
catch {
    Show-Failure $_.Exception.Message
}
