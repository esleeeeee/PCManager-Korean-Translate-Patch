$ErrorActionPreference = "SilentlyContinue"

$Port = 9222
$InstallRoot = Join-Path $env:LOCALAPPDATA "PCManagerKoPatch"
$LogPath = Join-Path $InstallRoot "agent.log"
$ConfigKey = "HKCU:\Software\PCManagerKoPatch"

New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null

function Write-Log {
    param([string]$Message)

    try {
        if ((Test-Path $LogPath) -and ((Get-Item $LogPath).Length -gt 524288)) {
            Remove-Item $LogPath -Force
        }

        Add-Content `
            -LiteralPath $LogPath `
            -Encoding UTF8 `
            -Value ("{0} {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"), $Message)
    }
    catch {}
}

$CreatedNew = $false
$Mutex = New-Object System.Threading.Mutex(
    $true,
    "Local\PCManagerKoPatchAgent",
    [ref]$CreatedNew
)

if (-not $CreatedNew) {
    exit
}

try {
    New-Item -Path $ConfigKey -Force | Out-Null
    New-ItemProperty -Path $ConfigKey -Name "AgentPid" -PropertyType DWord -Value $PID -Force | Out-Null
    New-ItemProperty -Path $ConfigKey -Name "Status" -PropertyType String -Value "Running" -Force | Out-Null
    New-ItemProperty -Path $ConfigKey -Name "LastStart" -PropertyType String -Value (Get-Date).ToString("s") -Force | Out-Null
}
catch {}

Write-Log "agent-start pid=$PID"

function Send-CDP {
    param(
        [System.Net.WebSockets.ClientWebSocket]$Socket,
        [int]$Id,
        [string]$Method,
        $Params,
        [string]$SessionId
    )

    $Object = [ordered]@{
        id = $Id
        method = $Method
    }

    if ($null -ne $Params) {
        $Object["params"] = $Params
    }

    if ($SessionId) {
        $Object["sessionId"] = $SessionId
    }

    $Json = $Object | ConvertTo-Json -Compress -Depth 20
    $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Json)
    $Segment = New-Object 'System.ArraySegment[byte]' -ArgumentList @(,$Bytes)

    $Socket.SendAsync(
        $Segment,
        [System.Net.WebSockets.WebSocketMessageType]::Text,
        $true,
        [System.Threading.CancellationToken]::None
    ).GetAwaiter().GetResult() | Out-Null
}

function Receive-CDP {
    param([System.Net.WebSockets.ClientWebSocket]$Socket)

    $Buffer = New-Object byte[] 65536
    $Stream = New-Object System.IO.MemoryStream

    try {
        while ($true) {
            $Segment = New-Object 'System.ArraySegment[byte]' -ArgumentList @(,$Buffer)

            $Result = $Socket.ReceiveAsync(
                $Segment,
                [System.Threading.CancellationToken]::None
            ).GetAwaiter().GetResult()

            if ($Result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                return $null
            }

            $Stream.Write($Buffer, 0, $Result.Count)

            if ($Result.EndOfMessage) {
                break
            }
        }

        return [System.Text.Encoding]::UTF8.GetString($Stream.ToArray())
    }
    finally {
        $Stream.Dispose()
    }
}

$InjectionScript = @"
(() => {
    if (window.__PCMAN_KOREAN_PATCH_ACTIVE__) {
        return;
    }

    window.__PCMAN_KOREAN_PATCH_ACTIVE__ = true;

    const install = () => {
        try {
            const webview = window.chrome && window.chrome.webview;

            if (!webview || typeof webview.postMessage !== 'function') {
                return false;
            }

            if (webview.__PCMAN_KOREAN_PATCHED__) {
                return true;
            }

            const originalPostMessage = webview.postMessage.bind(webview);

            const patchedPostMessage = function(data) {
                let output = data;

                try {
                    if (typeof data === 'string') {
                        const request = JSON.parse(data);

                        if (request && request.type === 'SmartTranslateRequest') {
                            request.message = request.message || {};

                            if (!request.message.targetLanguage) {
                                request.message.targetLanguage = 'ko';
                            }

                            output = JSON.stringify(request);
                        }
                    }
                    else if (
                        data &&
                        typeof data === 'object' &&
                        data.type === 'SmartTranslateRequest'
                    ) {
                        data.message = data.message || {};

                        if (!data.message.targetLanguage) {
                            data.message.targetLanguage = 'ko';
                        }

                        output = data;
                    }
                }
                catch (_) {}

                return originalPostMessage(output);
            };

            try {
                Object.defineProperty(webview, 'postMessage', {
                    value: patchedPostMessage,
                    configurable: true
                });
            }
            catch (_) {
                try {
                    webview.postMessage = patchedPostMessage;
                }
                catch (_) {
                    return false;
                }
            }

            try {
                Object.defineProperty(webview, '__PCMAN_KOREAN_PATCHED__', {
                    value: true,
                    configurable: true
                });
            }
            catch (_) {}

            return true;
        }
        catch (_) {
            return false;
        }
    };

    if (!install()) {
        const timer = setInterval(() => {
            if (install()) {
                clearInterval(timer);
            }
        }, 25);

        setTimeout(() => clearInterval(timer), 10000);
    }
})();
"@

while ($true) {
    $Socket = $null

    try {
        $Version = $null

        while ($null -eq $Version) {
            try {
                $Version = Invoke-RestMethod `
                    -Uri "http://127.0.0.1:$Port/json/version" `
                    -TimeoutSec 1
            }
            catch {
                Start-Sleep -Seconds 1
            }
        }

        $Socket = New-Object System.Net.WebSockets.ClientWebSocket
        $Uri = [System.Uri]$Version.webSocketDebuggerUrl

        $Socket.ConnectAsync(
            $Uri,
            [System.Threading.CancellationToken]::None
        ).GetAwaiter().GetResult() | Out-Null

        Write-Log "cdp-connected"

        $Id = 1

        Send-CDP $Socket $Id "Target.setDiscoverTargets" @{
            discover = $true
        } $null
        $Id++

        Send-CDP $Socket $Id "Target.setAutoAttach" @{
            autoAttach = $true
            waitForDebuggerOnStart = $false
            flatten = $true
        } $null
        $Id++

        while ($Socket.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
            $Raw = Receive-CDP $Socket

            if (-not $Raw) {
                break
            }

            try {
                $Message = $Raw | ConvertFrom-Json
            }
            catch {
                continue
            }

            if ($Message.method -eq "Target.attachedToTarget") {
                $SessionId = [string]$Message.params.sessionId
                $Target = $Message.params.targetInfo

                if ($Target.type -eq "page") {
                    Send-CDP $Socket $Id "Runtime.evaluate" @{
                        expression = $InjectionScript
                        returnByValue = $true
                    } $SessionId
                    $Id++

                    try {
                        New-ItemProperty `
                            -Path $ConfigKey `
                            -Name "LastInject" `
                            -PropertyType String `
                            -Value (Get-Date).ToString("s") `
                            -Force | Out-Null
                    }
                    catch {}

                    Write-Log ("inject title={0} url={1}" -f [string]$Target.title, [string]$Target.url)
                }
            }
        }
    }
    catch {
        Write-Log ("loop-error " + $_.Exception.Message)
    }

    if ($null -ne $Socket) {
        try {
            $Socket.Abort()
            $Socket.Dispose()
        }
        catch {}
    }

    Start-Sleep -Seconds 1
}
