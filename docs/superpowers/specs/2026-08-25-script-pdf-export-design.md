# 스크립트 PDF Export 기능 설계

**날짜:** 2026-08-25
**상태:** 구현 완료 (2026-08-27)
**상위 문서:** `docs/superpowers/specs/2026-08-14-script-html-export-design.md`

---

## 1. 배경

`core/script-panel.js:141` `exportScript()`가 이미 이중 자막 전체를 단일 HTML
파일로 내보낸다. 이전 설계(2026-08-14)는 PDF를 명시적으로 범위 밖에 두면서
"사용자가 브라우저 인쇄 기능으로 변환하면 된다"고 판단했다. 실제로는 그 경로가
UI에 드러나지 않아 사용자가 존재를 알 수 없고, 내보낸 HTML에 인쇄용 스타일이
없어 그대로 인쇄하면 줄이 페이지 경계에서 잘린다.

이번 기능은 내보내기 버튼에서 **HTML / PDF를 사용자가 선택**하게 하고, PDF
경로를 브라우저 인쇄 대화상자로 연결한다.

## 2. 범위

- **출력 포맷:** HTML(기존, 변경 없음) + PDF(신규, 인쇄 대화상자 경유).
- **PDF 생성 방식:** 브라우저 인쇄 엔진. PDF 생성 라이브러리를 번들하지 않는다.
- **진입점:** 스크립트 패널 헤더 `⬇` 버튼(드롭다운 메뉴), 설정 패널 내보내기
  섹션(행 2개).
- **범위 밖:** jsPDF 등 직접 PDF 생성, 한글 폰트 임베딩, 여러 영상 묶어서
  내보내기, 클라우드 저장/공유.

### 2.1 jsPDF를 쓰지 않는 이유

모국어 자막이 한국어라 jsPDF 기본 폰트로는 렌더링되지 않는다. Noto Sans KR을
서브셋해 base64로 임베드해도 통상 2~5MB가 확장에 상시 포함된다. 또한 jsPDF의
HTML 렌더링은 신뢰도가 낮아 실무에서는 좌표 기반으로 줄을 직접 그리게 되고,
그러면 HTML 템플릿과 PDF 레이아웃 코드를 이중으로 관리해야 한다. 자막 스크립트는
표·이미지 없는 순수 텍스트 문서라 브라우저 인쇄 엔진이 잘 처리하는 종류이고,
페이지 나눔 품질은 `@media print`로 충분히 확보된다.

## 3. 아키텍처

### 3.1 왜 확장 페이지를 거치는가

콘텐츠 스크립트가 만든 `blob:` URL을 새 탭 최상위로 여는 것은 호스트 페이지의
CSP 영향을 받는다. Netflix·Disney+는 CSP가 엄격해 이 경로가 차단될 수 있다.
확장 자신의 페이지(`chrome-extension://` 오리진)는 호스트 페이지 CSP의 영향을
받지 않으므로, **인쇄는 확장 페이지에서 수행**한다.

HTML 문자열은 장편 영화에서 수백 KB에 달할 수 있어 URL 쿼리로 넘길 수 없다.
`chrome.storage.session`에 임시 키로 넣고 id만 URL로 전달한다.

**저장은 서비스 워커가 한다.** `chrome.storage.session`의 기본 접근 수준은
`TRUSTED_CONTEXTS`라서 콘텐츠 스크립트에서는 읽고 쓸 수 없다. 콘텐츠 스크립트가
직접 저장하려면 `chrome.storage.session.setAccessLevel()`로 접근 수준을
`TRUSTED_AND_UNTRUSTED_CONTEXTS`로 열어야 하는데, 이는 4개 호스트 사이트의
모든 콘텐츠 스크립트에 세션 저장소를 상시 노출시키는 대가가 있다. HTML을
메시지 페이로드로 넘기면 접근 수준을 건드릴 필요가 없다 — 서비스 워커는
신뢰 컨텍스트라 기본값 그대로 접근 가능하다.

### 3.2 데이터 흐름 (PDF 경로)

```
[콘텐츠 스크립트]  script-panel.js
  html = _buildExportHtml(cues, nativeCues, meta)
        │
        └─ chrome.runtime.sendMessage({ type: 'EH_EXPORT_PRINT', payload: { html } })
                    │
[서비스 워커]  background/service_worker.js
                    │
                    ├─ id = crypto.randomUUID()
                    ├─ chrome.storage.session.set({ [`eh_print_${id}`]: html })
                    └─ chrome.tabs.create({ url: getURL(`export/print.html?id=${id}`) })
                                │
[확장 페이지]  export/print.html + export/print.js
                                │
                                ├─ chrome.storage.session.get(`eh_print_${id}`)
                                ├─ chrome.storage.session.remove(`eh_print_${id}`)
                                ├─ DOMParser로 파싱 → <style> + body 내용만 이식
                                ├─ await document.fonts.ready
                                └─ window.print()
```

`print.html`은 확장 페이지라 신뢰 컨텍스트이므로 `storage.session`을 그대로
읽는다.

**주입 안전성** — 자막 원문은 `_escapeHtml()`로 이미 이스케이프되지만, 방어적으로
전체 문서를 `documentElement.innerHTML`에 통째로 넣지 않고 `DOMParser`로 파싱해
`<style>`과 `<body>` 자식만 옮긴다. 더불어 MV3 확장 페이지의 기본 CSP
(`script-src 'self'`)가 인라인 스크립트와 인라인 이벤트 핸들러 실행을 막으므로,
설령 이스케이프가 뚫려도 스크립트는 실행되지 않는다.

권한 추가는 없다 — `storage`와 `tabs`는 매니페스트에 이미 있다.

### 3.3 HTML 경로

변경 없음. `Blob` + `URL.createObjectURL` + `<a download>` 그대로.

## 4. 변경 대상

### 4.1 `core/script-panel.js`

- `_buildExportHtml(cues, nativeCuesArr, meta)` → 인라인 `<style>`에
  `@media print` 블록을 추가한다. 시그니처는 그대로다. 인쇄 스타일은 HTML
  다운로드 경로에도 항상 포함한다 — 사용자가 저장한 HTML을 직접 인쇄해도
  동일하게 조판되어야 하므로 두 경로를 분기할 이유가 없다.
- `exportScript()` → `exportScriptHtml()` / `exportScriptPdf()`로 분리하고,
  공통 부분(빈 자막 가드, meta 조회, HTML 생성)은 `_prepareExport()`로 묶는다.
- `⬇` 버튼 클릭 → 드롭다운 토글.
- 공개 API: `window.EH.ScriptPanel`에 `exportScriptHtml`, `exportScriptPdf`를
  노출한다. 기존 `exportScript`는 설정 패널이 호출 중이므로 제거하지 않고
  `exportScriptHtml`의 별칭으로 남긴다.

### 4.2 `core/settings-panel.js`

`core/settings-panel.js:80`의 "스크립트 내보내기" 행 하나를 두 행으로 나눈다.
기존 확장자 칩 클래스(`.eh-settings-export-ext`)를 재사용한다.

```
내보내기
  ┌ 스크립트 내보내기         .html  ┐  ← primary
  ├ 스크립트 내보내기         .pdf   ┤
  └ 저장 항목 내보내기      .sqlite  ┘
```

### 4.3 `ui/overlay.css`

드롭다운 메뉴 스타일 추가 (`.eh-panel-export-menu`, `.eh-panel-export-item`).
기존 토큰(`--eh-accent`, `--eh-font-mono`)을 쓰고, 패널 헤더 기준으로
`position: absolute`, 헤더보다 위 `z-index`.

### 4.4 신규 `export/print.html`, `export/print.js`

확장 페이지. MV3는 인라인 스크립트를 금지하므로 JS는 별도 파일로 분리한다.
`print.html`은 뼈대만 갖고, `print.js`가 storage에서 읽은 HTML을 주입한 뒤
인쇄를 띄운다.

### 4.5 `background/service_worker.js`

`EH_EXPORT_PRINT` 메시지 핸들러 추가 — id를 받아 확장 페이지를 새 탭으로 연다.

### 4.6 `manifest.json` — 변경 없음

확장 자신이 `chrome.tabs.create`로 여는 확장 페이지는 매니페스트 등록이
필요 없다. 패키지 안에 파일이 존재하기만 하면 된다.
`web_accessible_resources`는 호스트 페이지가 접근할 리소스에만 필요한데,
`print.html`은 호스트 페이지가 접근하지 않으므로 등록하지 않는다 — 등록하면
오히려 임의의 사이트가 이 페이지를 열 수 있게 되어 불필요한 노출이 된다.

## 5. UI

### 5.1 스크립트 패널 드롭다운

`core/script-panel.js:274`의 `⬇` 버튼 아래에 앵커된 메뉴:

```
  [⤢] [⬇]
        └─────────────────┐
          HTML로 저장 .html │
          PDF로 저장   .pdf │
        └─────────────────┘
```

동작:
- `⬇` 클릭 → 메뉴 토글
- 항목 클릭 → 해당 내보내기 실행 후 메뉴 닫기
- 메뉴 바깥 클릭 / `Esc` → 닫기
- 패널이 숨겨지거나 임베드↔고정 모드가 전환될 때 → 닫기 (메뉴가 이전 위치에
  떠 있는 것을 막기 위함)

### 5.2 인쇄 스타일 (`@media print`)

- `.row { break-inside: avoid; }` — 한 자막 줄이 페이지 경계에서 갈리지 않게
- `header { break-after: avoid; }`
- 여백 `@page { margin: 18mm 14mm; }`
- 화면 전용 요소 숨김 (현재 내보낸 HTML에는 없지만 향후 대비)

## 6. 에러 처리

- `enCues`가 비어있으면 → 드롭다운을 열지 않고 기존과 동일하게
  "내보낼 자막이 없어요" 토스트.
- 서비스 워커의 `chrome.storage.session.set` 실패(용량 초과 등) → `{ success:
  false }`를 반환하고 탭을 열지 않는다. 콘텐츠 스크립트는 이를 받아 "PDF
  내보내기에 실패했어요" 토스트를 띄운다. `chrome.storage.session` 기본
  할당량은 10MB로 자막 HTML(수백 KB)에는 충분하지만 방어한다.
- `print.js`가 id에 해당하는 항목을 못 찾은 경우(탭 새로고침 등으로 이미
  삭제됨) → 페이지에 "내보낼 스크립트를 찾을 수 없어요. 다시 시도해 주세요."
  를 표시하고 `window.print()`를 호출하지 않는다.
- 확장 컨텍스트 무효화(`chrome.runtime.sendMessage` 실패, 확장 재로드 직후)
  → 토스트 안내.

## 7. 테스트

- `_buildExportHtml()` 단위 검증: 인쇄 스타일 블록 포함 여부, 기존 이스케이핑·
  구조 회귀 없음.
- `print.js`의 storage 조회 실패 분기 — 인쇄가 호출되지 않는지 확인.
- 인쇄 대화상자 자체는 브라우저 네이티브 UI라 자동 테스트 불가 → 4개 플랫폼
  (YouTube/Netflix/Disney+/쿠팡플레이)에서 수동 확인. 특히 **Netflix·Disney+
  에서 새 탭이 실제로 열리는지**가 이 설계의 핵심 검증 항목이다.

## 8. 범위 밖 (재확인)

- jsPDF 등 라이브러리 기반 직접 PDF 생성
- PDF에 한글 폰트 임베딩
- 여러 영상 묶어서 내보내기
- 클라우드 저장/공유
