$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

$Report = Join-Path ([Environment]::GetFolderPath("Desktop")) ("PCManagerKoPatch-Diagnostic-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".txt")
$ConfigKey = "HKCU:\Software\PCManagerKoPatch"
$RunKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$WebViewKey = "HKCU:\Software\Policies\Microsoft\Edge\WebView2\AdditionalBrowserArguments"
$InstallRoot = Join-Path $env:LOCALAPPDATA "PCManagerKoPatch"
$AgentLog = Join-Path $InstallRoot "agent.log"
$StartupLauncher = Join-Path ([Environment]::GetFolderPath("Startup")) "PCManagerKoPatch.vbs"

function L([string]$s = "") { Add-Content -LiteralPath $Report -Encoding UTF8 -Value $s }
function S([string]$s) { L ""; L ("==== " + $s + " ====") }

Set-Content -LiteralPath $Report -Encoding UTF8 -Value "PC Manager Korean Translate Patch Diagnostic"
L ("Generated: " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
L ("User: " + $env:USERNAME)
L ("Computer: " + $env:COMPUTERNAME)

S "Windows"
try {
  $os = Get-CimInstance Win32_OperatingSystem
  L ("Caption: " + $os.Caption)
  L ("Version: " + $os.Version)
  L ("Build: " + $os.BuildNumber)
} catch { L ("OS query failed: " + $_.Exception.Message) }
L ("PowerShell: " + $PSVersionTable.PSVersion)

S "PC Manager package"
try {
  $app = Get-AppxPackage Microsoft.MicrosoftPCManager
  if ($app) {
    L ("Version: " + $app.Version)
    L ("InstallLocation: " + $app.InstallLocation)
    $exe = Join-Path $app.InstallLocation "PCManager\MSPCManager.exe"
    L ("MSPCManager.exe exists: " + (Test-Path $exe))
  } else { L "NOT FOUND" }
} catch { L ("Package query failed: " + $_.Exception.Message) }

S "Patch files"
L ("InstallRoot: " + $InstallRoot)
L ("agent.ps1 exists: " + (Test-Path (Join-Path $InstallRoot "agent.ps1")))
L ("launch.vbs exists: " + (Test-Path (Join-Path $InstallRoot "launch.vbs")))
L ("agent.log exists: " + (Test-Path $AgentLog))
L ("Startup VBS exists: " + (Test-Path $StartupLauncher))

S "Patch registry"
try {
  $cfg = Get-ItemProperty -LiteralPath $ConfigKey
  foreach ($p in @("InstallVersion","InstallRoot","AgentPid","Status","LastStart","LastInject","HadPreviousBrowserArguments","PreviousBrowserArguments")) {
    if ($cfg.PSObject.Properties.Name -contains $p) { L ("{0}: {1}" -f $p, $cfg.$p) }
    else { L ("{0}: <missing>" -f $p) }
  }
} catch { L "Patch registry key missing or unreadable." }

S "Startup registration"
try {
  $run = (Get-ItemProperty -LiteralPath $RunKey -Name "PCManagerKoPatchAgent" -ErrorAction Stop).PCManagerKoPatchAgent
  L ("Run entry: " + $run)
} catch { L "Run entry: <missing>" }
L ("Startup VBS path: " + $StartupLauncher)

S "WebView2 policy"
try {
  $args = (Get-ItemProperty -LiteralPath $WebViewKey -Name "MSPCManager.exe" -ErrorAction Stop)."MSPCManager.exe"
  L ("MSPCManager.exe arguments: " + $args)
} catch { L "MSPCManager.exe arguments: <missing>" }

S "Processes"
try {
  Get-CimInstance Win32_Process |
    Where-Object {
      $_.Name -match 'MSPCManager|powershell|msedgewebview2' -and (
        $_.Name -match 'MSPCManager' -or
        $_.CommandLine -match 'PCManagerKoPatch|remote-debugging-port=9222|PC Manager Store'
      )
    } |
    ForEach-Object {
      L ("PID={0} Name={1}" -f $_.ProcessId, $_.Name)
      L ("  CommandLine=" + $_.CommandLine)
    }
} catch { L ("Process query failed: " + $_.Exception.Message) }

S "Port 9222"
try {
  $listeners = Get-NetTCPConnection -State Listen -LocalPort 9222
  if ($listeners) {
    foreach ($x in $listeners) { L ("LISTEN {0}:{1} PID={2}" -f $x.LocalAddress, $x.LocalPort, $x.OwningProcess) }
  } else { L "NOT LISTENING" }
} catch { L "NOT LISTENING" }

try {
  $v = Invoke-RestMethod -Uri "http://127.0.0.1:9222/json/version" -TimeoutSec 2
  L ("CDP Browser: " + $v.Browser)
  L ("CDP Protocol: " + $v.'Protocol-Version')
} catch { L ("CDP /json/version failed: " + $_.Exception.Message) }

S "Agent log before test"
if (Test-Path $AgentLog) { Get-Content -LiteralPath $AgentLog -Tail 80 | ForEach-Object { L $_ } }
else { L "<no agent.log>" }

S "30 second live test"
$before = $null
try { $before = (Get-ItemProperty -LiteralPath $ConfigKey -Name "LastInject").LastInject } catch {}
L ("LastInject before: " + [string]$before)

Write-Host ""
Write-Host "PC Manager patch diagnostic" -ForegroundColor Cyan
Write-Host "================================"
Write-Host ""
Write-Host "30초 안에 Ctrl+Shift+A -> 영역 선택 -> 번역 -> 결과 확인 -> Esc" -ForegroundColor Yellow
Write-Host "진단은 뒤에서 자동으로 계속됩니다."
Write-Host ""

$seen = @{}
$foundCircle = $false
$end = (Get-Date).AddSeconds(30)
while ((Get-Date) -lt $end) {
  try {
    $targets = @(Invoke-RestMethod -Uri "http://127.0.0.1:9222/json/list" -TimeoutSec 1)
    foreach ($t in $targets) {
      $sig = "{0}|{1}|{2}" -f $t.id, $t.title, $t.url
      if (-not $seen.ContainsKey($sig)) {
        $seen[$sig] = $true
        L ("TARGET type={0} title={1} url={2}" -f $t.type, $t.title, $t.url)
      }
      if ($t.title -eq "Circle to Act" -or $t.url -like "http://localhost:8000/screenshot*") { $foundCircle = $true }
    }
  } catch {}
  Start-Sleep -Milliseconds 250
}

$after = $null
try { $after = (Get-ItemProperty -LiteralPath $ConfigKey -Name "LastInject").LastInject } catch {}
L ("Circle target observed: " + $foundCircle)
L ("LastInject after: " + [string]$after)
L ("LastInject changed: " + ($before -ne $after -and $null -ne $after))

S "Agent log after test"
if (Test-Path $AgentLog) { Get-Content -LiteralPath $AgentLog -Tail 120 | ForEach-Object { L $_ } }
else { L "<no agent.log>" }

S "Interpretation"
L "No port 9222 => WebView2 policy/restart problem."
L "No running agent => startup/launcher problem."
L "Circle target seen but LastInject unchanged => CDP attach/injection problem."
L "LastInject changed but translation still Chinese => PC Manager request structure/version changed."

Write-Host ""
Write-Host "완료. 이 파일을 ChatGPT에 올려주세요:" -ForegroundColor Green
Write-Host $Report -ForegroundColor Yellow
