# PC Manager Korean Translate Patch

Microsoft PC Manager의 `Ctrl+Shift+A` Circle to Act 번역 기능이 첫 번역을 중국어 간체로 표시하는 문제를 우회하는 비공식 패치입니다.

패치는 번역 요청인 `SmartTranslateRequest`에 대상 언어가 지정되지 않았을 때만 `targetLanguage: "ko"`를 추가합니다. 사용자가 번역 창에서 일본어, 영어 등 다른 언어를 직접 선택한 경우에는 해당 값을 변경하지 않습니다.

## 설치

1. GitHub 저장소에서 `Code > Download ZIP`으로 다운로드하거나 저장소를 clone합니다.
2. ZIP으로 받았다면 완전히 압축 해제합니다.
3. `install.bat`을 더블클릭합니다.
4. 아래 두 항목이 `[OK]`로 표시되고 `INSTALLATION SUCCESSFUL`이 나오면 설치가 완료된 것입니다.
5. `Ctrl+Shift+A`로 텍스트를 선택한 뒤 번역을 눌러 첫 결과가 한국어인지 확인합니다.
6. 설치가 끝난 뒤 다운로드하고 압축 해제한 폴더는 삭제해도 됩니다.

WebView2 사용자 정책을 수정할 수 있는 PC에서는 일반 권한으로 설치됩니다. 일부 PC는 `HKCU\Software\Policies`가 읽기 전용이라 관리자 권한이 필요합니다. 이 경우 설치기는 기존 파일·자동 실행·실행 중인 패치를 건드리기 전에 중단합니다. **같은 Windows 계정에서** `install.bat`을 우클릭 → **관리자 권한으로 실행**하세요. 조직에서 관리하는 PC는 관리자에게 문의하세요. 다른 관리자 계정으로 설치하면 그 계정에 적용되므로 피하세요.

**관리자 설치 후:** `SETUP SAVED - NORMAL RESTART REQUIRED`는 설정 저장 완료이며 번역 검증 완료가 아닙니다. 설치창을 닫고 PC Manager를 트레이에서 완전히 종료한 뒤 시작 메뉴에서 **일반 실행**하세요. 파일 탐색기에서 `%LOCALAPPDATA%\PCManagerKoPatch\launch.vbs`도 더블클릭하세요. 또는 Windows에서 로그아웃 후 다시 로그인하세요. 설치기는 PC Manager를 관리자 권한으로 자동 실행하지 않습니다. [WebView2는 관리자 권한으로 실행한 앱에서 로컬 설정으로 지정한 연결 옵션을 무시하기 때문입니다.](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/webview-features-flags)

## 제거

저장소를 다시 다운로드하거나 clone한 뒤 `uninstall.bat`을 더블클릭하면 됩니다.

## 설치되는 항목

사용자 프로필에 아래 파일이 설치됩니다.

```text
%LOCALAPPDATA%\PCManagerKoPatch\
  agent.ps1
  launch.vbs
  agent.log
```

로그인 자동 실행을 위해 다음 위치를 사용합니다.

```text
HKCU\Software\Microsoft\Windows\CurrentVersion\Run
Startup folder
```

Microsoft PC Manager의 WebView2에 연결하기 위해 다음 사용자 정책 값에 로컬 디버깅 인자를 추가합니다.

```text
HKCU\Software\Policies\Microsoft\Edge\WebView2\AdditionalBrowserArguments
```

디버깅 포트는 `127.0.0.1:9222`에만 바인딩됩니다. 제거 시 설치 전의 app-specific WebView2 인자를 복원합니다.

## 동작 원리

PC Manager의 Circle to Act는 WebView2 페이지에서 네이티브 PC Manager로 `SmartTranslateRequest`를 전송합니다.

기본 번역 요청에는 `targetLanguage`가 없고, 현재 PC Manager 버전에서는 이 경우 `zh-Hans`가 기본 대상 언어로 사용됩니다.

이 패치는 Circle to Act WebView가 생성될 때 `chrome.webview.postMessage`를 래핑하고 아래 조건에서만 요청을 수정합니다.

```javascript
if (
  request.type === "SmartTranslateRequest" &&
  !request.message.targetLanguage
) {
  request.message.targetLanguage = "ko";
}
```

따라서 다른 언어를 명시적으로 선택한 번역 요청은 변경하지 않습니다.

## 호환성

확인된 환경:

- Microsoft Store판 Microsoft PC Manager
- PC Manager 3.22.4.0
- Windows의 WebView2 기반 Circle to Act
- 2026년 9월 기준

PC Manager 업데이트로 `SmartTranslateRequest`, Circle to Act의 WebView 구조, WebView2 정책 동작이 변경되면 패치가 작동하지 않을 수 있습니다.

## 보안 참고

이 패치는 PC Manager WebView에 코드를 주입하기 위해 WebView2 원격 디버깅 기능을 로컬 호스트에 활성화합니다. 외부 네트워크에 포트를 열지는 않지만, 동일한 Windows 사용자 세션에서 실행 중인 로컬 프로세스가 해당 디버깅 포트에 접근할 가능성은 있습니다.

이 동작이 필요하지 않다면 `uninstall.bat`으로 패치를 제거하십시오.

## 문제 해결

진단 로그:

```text
%LOCALAPPDATA%\PCManagerKoPatch\agent.log
```

설치 직후 아래 메시지가 둘 다 표시되어야 합니다.

```text
[OK] Background agent is running.
[OK] PC Manager WebView2 endpoint is active.
```

재부팅 후 작동하지 않으면 `agent.log`와 PC Manager 버전을 Issue에 첨부해 주세요.

로그에 `agent-start`만 있고 `cdp-connected`가 없으면 번역 패치가 적용된 것이 아닙니다. 에이전트가 켜져 있다는 것과 PC Manager에 연결됐다는 것은 다릅니다. 특히 `Access to the registry key ... is denied`가 나오면 위의 권한 안내를 확인하세요.

개발 검증: `node --test tests/translation.test.cjs`는 기본 한국어 지정과 명시적 언어 선택 보존을 검사합니다. 실제 화면 번역 확인은 별도로 필요합니다.

## 라이선스

MIT License

## 면책

이 프로젝트는 비공식 커뮤니티 패치이며 Microsoft와 제휴하거나 Microsoft의 보증을 받지 않습니다. Microsoft PC Manager는 Microsoft의 제품입니다.
