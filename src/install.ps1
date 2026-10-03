$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Assert-WebViewPolicyWritable {
    # Check the closest existing parent without creating keys or changing ACLs.
    # Some PCs protect HKCU\Software\Policies even for the current user.
    $RelativePath = 'Software\Policies\Microsoft\Edge\WebView2\AdditionalBrowserArguments'
    while ($RelativePath) {
        $ReadKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($RelativePath)
        if ($null -ne $ReadKey) {
            $ReadKey.Dispose()
            try {
                $WriteKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($RelativePath, $true)
                if ($null -eq $WriteKey) { throw 'Registry key could not be opened for writing.' }
                $WriteKey.Dispose()
                return
            }
            catch {
                throw 'The WebView2 policy is read-only for this account. No installation changes were made. Right-click install.bat and choose Run as administrator using the SAME Windows account, then run diagnose.bat. If this is an organization-managed PC, ask its administrator. Existing patch files and processes have been preserved.'
            }
        }
        $Separator = $RelativePath.LastIndexOf('\')
        if ($Separator -lt 0) { break }
        $RelativePath = $RelativePath.Substring(0, $Separator)
    }
    throw 'Unable to check WebView2 policy permissions. No installation changes were made.'
}

function Show-Failure {
    param([string]$Message)

    Write-Host ""
    Write-Host "[FAIL] $Message" -ForegroundColor Yellow
    Write-Host "No changes beyond the completed steps are hidden."
    Write-Host ""
    exit 1
}

try {
    $IsElevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
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

    # Fail before stopping the working agent or replacing startup registrations.
    Assert-WebViewPolicyWritable

    # An elevated setup only installs configuration. Runtime processes must stay
    # at normal user integrity: elevated WebView2 ignores these local flags.
    if (-not $IsElevated) {
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
    }

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
    if (-not (Test-Path -LiteralPath $ConfigKey)) { New-Item -Path $ConfigKey -Force | Out-Null }
    if (-not (Test-Path -LiteralPath $WebViewKey)) { New-Item -Path $WebViewKey -Force | Out-Null }

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

    # A repair install must retain the original uninstall backup, not replace it
    # with the debugging arguments from an earlier installation.
    $SavedConfig = Get-ItemProperty -LiteralPath $ConfigKey
    if ($SavedConfig.PSObject.Properties.Name -notcontains 'HadPreviousBrowserArguments') {
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
    }

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

    if (-not (Test-Path -LiteralPath $RunKey)) { New-Item -Path $RunKey -Force | Out-Null }
    New-ItemProperty `
        -Path $RunKey `
        -Name "PCManagerKoPatchAgent" `
        -PropertyType String `
        -Value $RunCommand `
        -Force | Out-Null

    New-ItemProperty -Path $ConfigKey -Name "InstallVersion" -PropertyType String -Value "1.0.0" -Force | Out-Null
    New-ItemProperty -Path $ConfigKey -Name "InstallRoot" -PropertyType String -Value $InstallRoot -Force | Out-Null
    if ($IsElevated) {
        Write-Host ""
        Write-Host "SETUP SAVED - NORMAL RESTART REQUIRED" -ForegroundColor Yellow
        Write-Host "PC Manager has NOT been launched with administrator rights."
        Write-Host "Close this installer, exit PC Manager from its tray menu, then reopen it normally."
        Write-Host "From File Explorer, double-click: $LauncherPath"
        Write-Host "Alternatively, sign out of Windows and sign back in to start both normally."
        Write-Host "Then run diagnose.bat and test Ctrl+Shift+A translation."
        Write-Host "Runtime connection and Korean translation have NOT yet been verified."
        exit 2
    }
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
