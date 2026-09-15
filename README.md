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

설치 시 관리자 권한은 필요하지 않습니다.

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

## 라이선스

MIT License

## 면책

이 프로젝트는 비공식 커뮤니티 패치이며 Microsoft와 제휴하거나 Microsoft의 보증을 받지 않습니다. Microsoft PC Manager는 Microsoft의 제품입니다.
