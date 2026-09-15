$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Show-Failure {
    param([string]$Message)

    Write-Host ""
    Write-Host "[FAIL] $Message" -ForegroundColor Yellow
    Write-Host "No changes beyond the completed steps are hidden."
    Write-Host ""
    exit 1
}

try {
    $Port = 9222
    $InstallRoot = Join-Path $env:LOCALAPPDATA "PCManagerKoPatch"
    $AgentSource = Join-Path $PSScriptRoot "agent.ps1"
    $AgentPath = Join-Path $InstallRoot "agent.ps1"
    $LauncherPath = Join-Path $InstallRoot "launch.vbs"
    $LogPath = Join-Path $InstallRoot "agent.log"

    $ConfigKey = "HKCU:\Software\PCManagerKoPatch"
    $RunKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    $WebViewKey = "HKCU:\Software\Policies\Microsoft\Edge\WebView2\AdditionalBrowserArguments"

    $StartupDirectory = [Environment]::GetFolderPath("Startup")
    $StartupLauncher = Join-Path $StartupDirectory "PCManagerKoPatch.vbs"

    Write-Host ""
    Write-Host "PC Manager Korean Translation Patch 1.0.0" -ForegroundColor Cyan
    Write-Host "=========================================="
    Write-Host ""

    if (-not (Test-Path $AgentSource)) {
        Show-Failure "src\agent.ps1 was not found. Extract the full repository ZIP before running install.bat."
    }

    $App = Get-AppxPackage Microsoft.MicrosoftPCManager -ErrorAction SilentlyContinue

    if (-not $App) {
        Show-Failure "Microsoft Store PC Manager was not found."
    }

    $PcManagerExe = Join-Path $App.InstallLocation "PCManager\MSPCManager.exe"

    if (-not (Test-Path $PcManagerExe)) {
        Show-Failure "MSPCManager.exe was not found in the Microsoft Store package."
    }

    # Stop an existing installed agent if present.
    try {
        $OldPid = (Get-ItemProperty -LiteralPath $ConfigKey -Name "AgentPid" -ErrorAction SilentlyContinue).AgentPid

        if ($OldPid) {
            $OldProcess = Get-Process -Id $OldPid -ErrorAction SilentlyContinue

            if ($OldProcess -and $OldProcess.ProcessName -ieq "powershell") {
                Stop-Process -Id $OldPid -Force -ErrorAction SilentlyContinue
            }
        }
    }
    catch {}

    Start-Sleep -Milliseconds 250

    # Remove older startup registrations from previous builds.
    Remove-ItemProperty -Path $RunKey -Name "PCManagerKoPatch" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $RunKey -Name "PCManagerKoPatchAgent" -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $StartupLauncher -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:LOCALAPPDATA\PCManagerKoPatch.ps1" -Force -ErrorAction SilentlyContinue

    New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null

    # Install the transparent source agent.
    Copy-Item -LiteralPath $AgentSource -Destination $AgentPath -Force

    # Hidden launcher used at sign-in.
    $Launcher = @'
Set sh = CreateObject("WScript.Shell")
ps = sh.ExpandEnvironmentStrings("%LOCALAPPDATA%\PCManagerKoPatch\agent.ps1")
cmd = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & ps & """"
sh.Run cmd, 0, False
'@

    [System.IO.File]::WriteAllText(
        $LauncherPath,
        $Launcher,
        (New-Object System.Text.UTF8Encoding($false))
    )

    Copy-Item -LiteralPath $LauncherPath -Destination $StartupLauncher -Force

    # Preserve any previous app-specific WebView2 arguments for clean uninstall.
    New-Item -Path $ConfigKey -Force | Out-Null
    New-Item -Path $WebViewKey -Force | Out-Null

    $HadPreviousArguments = $false
    $PreviousArguments = ""

    try {
        $PreviousArguments = (Get-ItemProperty `
            -LiteralPath $WebViewKey `
            -Name "MSPCManager.exe" `
            -ErrorAction Stop)."MSPCManager.exe"

        $HadPreviousArguments = $true
    }
    catch {}

    New-ItemProperty `
        -Path $ConfigKey `
        -Name "HadPreviousBrowserArguments" `
        -PropertyType DWord `
        -Value ([int]$HadPreviousArguments) `
        -Force | Out-Null

    New-ItemProperty `
        -Path $ConfigKey `
        -Name "PreviousBrowserArguments" `
        -PropertyType String `
        -Value ([string]$PreviousArguments) `
        -Force | Out-Null

    $Arguments = [string]$PreviousArguments
    $Arguments = [regex]::Replace($Arguments, '(?i)--remote-debugging-port(?:=|\s+)\d+', '')
    $Arguments = [regex]::Replace($Arguments, '(?i)--remote-debugging-address(?:=|\s+)\S+', '')
    $Arguments = ($Arguments.Trim() + " --remote-debugging-port=$Port --remote-debugging-address=127.0.0.1").Trim()

    New-ItemProperty `
        -Path $WebViewKey `
        -Name "MSPCManager.exe" `
        -PropertyType String `
        -Value $Arguments `
        -Force | Out-Null

    # Register two user-level startup paths for reliability.
    $RunCommand = 'wscript.exe "' + $LauncherPath + '"'

    New-Item -Path $RunKey -Force | Out-Null
    New-ItemProperty `
        -Path $RunKey `
        -Name "PCManagerKoPatchAgent" `
        -PropertyType String `
        -Value $RunCommand `
        -Force | Out-Null

    New-ItemProperty -Path $ConfigKey -Name "InstallVersion" -PropertyType String -Value "1.0.0" -Force | Out-Null
    New-ItemProperty -Path $ConfigKey -Name "InstallRoot" -PropertyType String -Value $InstallRoot -Force | Out-Null
    Remove-ItemProperty -Path $ConfigKey -Name "AgentPid" -ErrorAction SilentlyContinue

    # Start the background agent now.
    Start-Process `
        -FilePath "wscript.exe" `
        -ArgumentList "`"$LauncherPath`"" `
        -WindowStyle Hidden

    Start-Sleep -Milliseconds 700

    # Restart PC Manager so the WebView2 argument policy takes effect.
    Stop-Process -Name "MSPCManager" -Force -ErrorAction SilentlyContinue
    Stop-Process -Name "MSPCManagerCore" -Force -ErrorAction SilentlyContinue

    Get-CimInstance Win32_Process -Filter "Name='msedgewebview2.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like "*PC Manager Store*" } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }

    Start-Sleep -Milliseconds 800
    Start-Process $PcManagerExe

    # Verify both components without throwing noisy PowerShell errors.
    $AgentOk = $false
    $EndpointOk = $false

    for ($Attempt = 0; $Attempt -lt 30; $Attempt++) {
        try {
            $AgentPid = (Get-ItemProperty -LiteralPath $ConfigKey -Name "AgentPid" -ErrorAction SilentlyContinue).AgentPid

            if ($AgentPid) {
                $AgentProcess = Get-Process -Id $AgentPid -ErrorAction SilentlyContinue

                if ($AgentProcess -and $AgentProcess.ProcessName -ieq "powershell") {
                    $AgentOk = $true
                }
            }
        }
        catch {}

        try {
            $Version = Invoke-RestMethod `
                -Uri "http://127.0.0.1:$Port/json/version" `
                -TimeoutSec 1

            if ($Version.Browser) {
                $EndpointOk = $true
            }
        }
        catch {}

        if ($AgentOk -and $EndpointOk) {
            break
        }

        Start-Sleep -Milliseconds 500
    }

    Write-Host ""

    if ($AgentOk) {
        Write-Host "[OK] Background agent is running." -ForegroundColor Green
    }
    else {
        Write-Host "[FAIL] Background agent did not start." -ForegroundColor Yellow
    }

    if ($EndpointOk) {
        Write-Host "[OK] PC Manager WebView2 endpoint is active." -ForegroundColor Green
    }
    else {
        Write-Host "[FAIL] PC Manager WebView2 endpoint is not active." -ForegroundColor Yellow
    }

    Write-Host ""

    if (-not ($AgentOk -and $EndpointOk)) {
        Write-Host "Diagnostic log: $LogPath"
        exit 1
    }

    Write-Host "INSTALLATION SUCCESSFUL" -ForegroundColor Green
    Write-Host ""
    Write-Host "Test: Ctrl+Shift+A -> select text -> Translate"
    Write-Host "Installed at: $InstallRoot"
    Write-Host "The downloaded repository folder can now be deleted."
    Write-Host ""
    exit 0
}
catch {
    Show-Failure $_.Exception.Message
}
