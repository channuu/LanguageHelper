# 스크립트 HTML Export 기능 설계

**날짜:** 2026-08-14
**상태:** 승인됨
**상위 문서:** `docs/superpowers/specs/2026-07-17-english-helper-design.md`

---

## 1. 배경

`core/script-panel.js`는 현재 시청 중인 영상의 이중 자막(영어+모국어) 전체를
사이드 패널에 타임스탬프와 함께 렌더링한다. 이 스크립트를 브라우저 밖으로
가져가서 저장·공유·인쇄할 수 있는 방법이 없다. 이번 기능은 패널이 이미 갖고
있는 `enCues`/`nativeCues` 데이터를 그대로 독립된 HTML 파일로 내보낸다.

## 2. 범위

- **출력 포맷:** HTML만 (PDF는 범위 밖 — 사용자가 브라우저 인쇄 기능으로
  HTML을 PDF로 변환할 수 있어 사실상 커버됨).
- **진입점:** 사이드 패널 헤더에 export 아이콘 버튼 추가 (기존 접기/숨기기
  버튼 옆).
- **메타데이터:** 문서 상단에 콘텐츠 제목, 플랫폼, export 날짜를 포함.
- **범위 밖:** PDF 직접 생성, 여러 영상을 한 번에 묶어서 export, 클라우드
  저장/공유.

## 3. 아키텍처

`core/script-panel.js`에 `exportScript()` 함수를 추가한다. 기존 SQLite export
(`popup/popup.js`)가 이미 쓰고 있는 `Blob` + `URL.createObjectURL` +
`<a download>` 패턴을 그대로 재사용한다 — 새 의존성이나 라이브러리는 필요
없다.

**어댑터 참조 보관** — `setup(adapter)`는 현재 `adapter`를 모듈 스코프
변수에 저장하지 않고 즉시 소비만 한다 (`getSubtitleTracks()`,
`onTracksReady()` 호출 후 버림). export 시점에 `getPlatformMeta()`
(제목/플랫폼)를 호출하려면 어댑터 참조가 필요하므로, `setup()`에서
모듈 스코프 변수 `let currentAdapter`에 저장해둔다.

```js
let currentAdapter = null;

function setup(adapter) {
  currentAdapter = adapter;
  createDOM();
  // ... 기존 로직 그대로
}

function exportScript() {
  if (!enCues.length) {
    window.EH.showToast?.('내보낼 자막이 없어요');
    return;
  }
  const meta = currentAdapter?.getPlatformMeta() || { platform: '', title: '' };
  const html = _buildExportHtml(meta);
  const blob = new Blob([html], { type: 'text/html' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `${meta.title || 'script'}.html`;
  a.click();
  URL.revokeObjectURL(url);
}
```

## 4. HTML 문서 구조

`_buildExportHtml(meta)`가 반환하는 문자열은 완결된 단일 HTML 파일
(외부 리소스 의존 없음, 인라인 `<style>`):

- **상단**: 콘텐츠 제목(`meta.title`), 플랫폼(`meta.platform`), export 날짜
  (`new Date().toLocaleDateString()`)
- **본문**: `enCues`를 순회하며 각 줄마다 타임스탬프(`formatTime(cue.start)`,
  기존 함수 재사용) + 영어 자막 + `findNativeText(cue)`로 찾은 모국어 자막을
  나열 (기존 `renderList()`가 화면에 그리는 것과 동일한 매칭 로직 재사용)
- 모든 텍스트는 HTML 엔티티 이스케이핑 처리 (자막 원문에 `<`, `>`, `&` 등이
  포함될 수 있으므로 XSS/깨짐 방지)

## 5. UI

사이드 패널 헤더(`createDOM()`의 `header.innerHTML`)에 export 버튼 추가:

```js
header.innerHTML =
  '<span class="eh-panel-title">Script</span>' +
  '<button class="eh-panel-btn" id="eh-panel-export" title="스크립트 내보내기">⬇</button>' +
  '<button class="eh-panel-btn" id="eh-panel-hide">−</button>' +
  '<button class="eh-panel-btn" id="eh-panel-collapse">✕</button>';
```

클릭 리스너는 `createDOM()` 안에서 기존 `collapseBtn`/`hideBtn` 리스너와
같은 위치에 추가.

## 6. 에러 처리

- `enCues`가 비어있을 때(로딩 중이거나 트랙 없음) → export 버튼을 누르면
  토스트로 "내보낼 자막이 없어요" 안내, 파일 생성하지 않음.
- `currentAdapter`가 아직 설정되지 않은 극히 드문 타이밍(패널이 뜨기 전)에는
  제목/플랫폼을 빈 문자열로 폴백, export 자체는 진행.

## 7. 테스트

- `_buildExportHtml()`의 HTML 이스케이핑, 구조(제목/타임스탬프/자막 포함
  여부)에 대한 헤드리스 Chrome 시뮬레이션 검증 — 지금까지 이 프로젝트의
  다른 어댑터 작업과 동일한 방식.
- 실제 다운로드 트리거(`<a>.click()`)는 브라우저 UI 동작이라 자동 테스트
  범위에서 제외, 수동 확인.

## 8. 범위 밖 (재확인)

- PDF 직접 생성
- 여러 영상 묶어서 export
- 클라우드 저장/공유
