# 영상 오버레이 — 저장 목록 패널 & 스크립트 패널 재설계 (Spec)

## 1. 배경

2026-08-21에 완료된 `feature/video-overlay-redesign` 브랜치(상단 설정 바, 설정 패널, 스크립트 패널 검색/저장상태/자동스크롤)를 실제 목업과 다시 대조하는 과정에서, `English Helper UI.dc.html` §1h/1i가 마지막으로 확인했던 시점 이후 상당히 갱신되어 있는 것을 발견했다. Claude Design MCP로 라이브 프로젝트를 다시 임포트해 DCLogic 스크립트 전체(`renderVals()`)를 확인한 결과, 색상 토큰 문제(별도로 이미 수정·머지됨) 외에 구조적으로도 아래 3가지가 새로 추가/변경되어 있었다:

1. 상단 바에 "저장 목록" 버튼이 신설되어, 툴바 팝업이 하던 일(단어/문장 열람, SQLite 내보내기)을 영상 오버레이 자체에서 처리
2. 스크립트 패널이 검색/필터/복사/NOW배지/실크기확장 등으로 크게 확장
3. 슬라이더 눈금 값이 미세하게 변경

이 스펙은 이 3가지를 다루는 후속 작업을 정의한다.

## 2. 범위

**포함:**
- 툴바 팝업(`popup/`) 및 `manifest.json`의 `action`(툴바 아이콘) 완전 제거
- 새 라이브러리("저장 목록") 패널 — `core/library-panel.js`
- 상단 바의 정적 "저장 {count}" 표시를 "저장 목록" 버튼으로 교체 (아이콘 배지+클릭 가능)
- 상단 바 로고 옆 `icon48.png` 아이콘 추가
- 스크립트 패널 재설계: 검색창 카운트 배지, 필터 칩 3종, 줄별 복사 버튼, NOW 배지, 진짜 자동 스크롤 토글 스위치, 헤더 ⤢ 실제-크기 확장, 푸터 형식 변경
- 설정 패널 슬라이더 눈금 값을 최신 목업 값으로 정확히 맞춤
- `background/service_worker.js`의 죽은 `TOGGLE_EXTENSION` 케이스 제거

**제외 (범위 밖):**
- §1i의 "PANEL BEHAVIOR" 우측 설명 컬럼은 UI로 구현하지 않는다 (목업 내 개발자용 주석 섹션이며, 실제 화면 요소가 아님) — 단, 그 설명이 서술하는 동작 원칙(아래 §6 참고)은 구현에 반영한다.
- 자막 오버레이 자체(`core/subtitle-engine.js`)의 드래그/리사이즈 동작은 이번에도 변경하지 않는다.
- 스크립트 내보내기 포맷은 여전히 HTML만 유지한다 (export 버튼 라벨의 `.srt/.txt` 텍스트는 무시, 기존 방침 유지).

## 3. 팝업/아이콘 제거

- `manifest.json`에서 `"action": { "default_popup": "popup/popup.html" }` 블록을 완전히 삭제한다 — 툴바에 아이콘 자체가 뜨지 않는다.
- `popup/popup.html`, `popup/popup.js` 삭제.
- `background/service_worker.js`의 `case 'TOGGLE_EXTENSION':` 블록 삭제 — 이 메시지를 보내는 코드가 이미 저장소 어디에도 없음을 확인했다(죽은 코드).
- `core/sqlite-export.js`(Task 1에서 추출한 공유 모듈)는 그대로 유지 — 이제 `core/library-panel.js`만 사용.

## 4. 상단 바 변경

`core/topbar.js` 수정:
- 브랜드 영역에 `<img>` 태그로 `icon48.png` 아이콘 추가 (텍스트 앞, 20×20px). `manifest.json`의 `web_accessible_resources`에 이미 `assets/*` 관련 항목이 있는지 확인 후 없으면 추가.
- 기존 `refreshCount`/`#eh-topbar-count`(정적 텍스트)를 제거하고, 그 자리에 클릭 가능한 "저장 목록" 버튼을 추가한다:
  - 북마크 아이콘(SVG) + "저장 목록" 텍스트 + 개수 배지(`GET_ALL`의 words+sentences 합계, 기존 `refreshCount` 로직 재사용)
  - 클릭 시 `LibraryPanel`을 토글하는 CustomEvent(`eh-library-toggle`, `eh-settings-toggle`과 동일 패턴)를 dispatch
  - **설정 버튼과 상호 배타적**: 라이브러리 패널이 열리면 설정 패널은 닫히고, 반대도 마찬가지 — `core/library-panel.js`와 `core/settings-panel.js` 양쪽에서 서로의 CustomEvent를 리슨해 자기 자신을 닫는 방식으로 구현 (직접 결합 없이 이벤트로만 연결, 기존 `eh-overlay-toggled`/`eh-panel-toggled` 패턴과 동일한 느슨한 결합 유지)
  - Task 2/3 whole-branch review에서 추가했던 `eh-item-saved` 이벤트 리스너는 그대로 재사용 — 저장이 일어날 때마다 이 배지도 갱신되어야 하므로.

## 5. 라이브러리("저장 목록") 패널 — `core/library-panel.js` (신규)

`core/topbar.js`/`core/settings-panel.js`와 동일한 `window.EH.*` IIFE 모듈 관례를 따르는 새 파일.

- **위치**: `position:fixed; top:52px; right:132px; ...` (설정 패널의 `right:16px`와 다른 오프셋 — 목업 그대로 따름). 폭 330px.
- **헤더**: "SAVED LIBRARY" 타이틀 + ✕ 닫기
- **탭**: 단어 {count} / 문장 {count} (클릭으로 전환) + 우측에 "이 영상 {N}" (현재 비디오의 `contentId`로 필터링한 저장 수 — Task 4의 `savedTextSet`/contentId 스코핑 패턴 재사용)
- **카드 목록** (스크롤 영역):
  - 단어 카드: word + ipa + 뜻(ko) + 플랫폼 배지 + "▸ {time}" (클릭 시 `adapter.seekTo(item.timestamp)` — **신규 기능**, 저장된 timestamp로 시크)
  - 문장 카드: en + ko + 플랫폼 배지 + "▸ {time}" (동일하게 시크)
- **푸터**: SQLite 내보내기 버튼 (`window.EH.SqliteExport.exportAll` 재사용, 기존 설정 패널의 내보내기 버튼과 동일한 에러 처리 패턴) + 안내 텍스트
- **데이터 로드**: `chrome.runtime.sendMessage({type:'GET_ALL'})` — 팝업이 하던 것과 동일한 패턴. 패널이 열릴 때마다(매번 `show()` 호출 시) 새로 fetch해서 최신 상태 유지 (팝업 없이 이 패널이 유일한 열람 경로가 되므로, 저장 직후 반영이 특히 중요).

## 6. 스크립트 패널 재설계 — `core/script-panel.js` 수정

기존 Task 4에서 이미 구현된 검색(`matchesQuery`)·저장상태(`savedTextSet`, contentId 스코핑)·자동스크롤 게이팅은 그대로 유지하고, 그 위에 다음을 추가/변경한다:

- **헤더**: 버튼 2개(─/✕) → 3개(⤢/─/✕)
  - **⤢ (확장)**: 클릭 시 패널이 §1i처럼 실제 크기(396×706px 상당)로 확장되는 토글. 확장 상태에서는 패널 자체가 더 넓어지고(현재 `panelW` 로직 확장), 확장 모드 전용 CSS 클래스(`#eh-panel.expanded`)로 처리. 다시 누르면 원래 크기로.
  - **─**: 기존 hide 버튼(그대로 유지, `eh-panel-toggled` 디스패치도 유지)
  - **✕**: 기존 collapse 버튼(그대로 유지)
- **영상 제목 표시줄**: 헤더 바로 아래, `adapter.getPlatformMeta().title`을 표시 (ellipsis 처리)
- **검색창**: 기존 input 옆에 남은 줄 수 배지 추가 (검색어 없으면 "{총 줄 수}줄", 있으면 "{매칭 수}건")
- **필터 칩 3개**: 전체 / 저장한 줄 {N} / 미저장 — 검색어와 AND로 결합해서 `renderList()`의 필터링에 추가 조건으로 적용 (기존 `matchesQuery`에 필터 조건을 곱해서 사용)
- **NOW 배지**: 현재 재생 중인 줄의 시간 표시 아래에 작은 "NOW" 라벨 추가 (`highlight()`가 이미 활성 줄을 알고 있으므로 그 정보를 재사용)
- **복사 버튼**: 각 줄 우측에 저장 버튼과 별도로 추가. 클릭 시 `navigator.clipboard.writeText(cue.text)` (영어 원문만, 실패해도 조용히 무시 — 클립보드 API가 막힌 컨텍스트 대비), 1.4초간 체크 아이콘으로 전환 후 원래 아이콘 복귀. **저장 기록을 전혀 남기지 않는다** (Storage 호출 없음, §1i의 "복사와 저장을 분리" 원칙).
- **자동 스크롤**: 기존 텍스트 배지(`.eh-panel-autoscroll`)를 실제 토글 스위치 UI로 교체 (topbar의 토글 스위치와 동일한 마크업/스타일 재사용)
- **푸터 텍스트**: "이 영상에서 저장 {N}" → "저장 {N} / {총 줄 수}줄" 형식으로 변경

## 7. 설정 패널 슬라이더 눈금 정밀 수정

`core/settings-panel.js`의 `EN_TICKS`/`KO_TICKS` 상수를 최신 목업 값으로 교체:
- `EN_TICKS = [12, 17, 22, 26, 31, 36, 41, 46, 52]` (기존: `[12,17,22,27,32,37,42,47,52]`)
- `KO_TICKS = [10, 14, 18, 22, 26, 32, 38, 44, 48]` (기존: `[10,14,18,22,26,30,34,41,48]`)

## 8. 저장 상태 매칭 방식 (설계 결정)

목업의 DCLogic은 `scSavedIds`를 **시간(time) 문자열**로 키를 잡지만(`t === '2:23'`), 이 프로젝트의 실제 저장 데이터는 시간이 아니라 **원문 텍스트**로 매칭하는 방식이 Task 4에서 이미 구현·검증되어 있다. 실제 저장소(`chrome.storage.local`)에 저장되는 문장 레코드는 고유 ID가 없는 자유 형식 텍스트이고, 시간 기반 키는 VTT 큐 타이밍이 소스마다 미세하게 달라질 수 있어 텍스트보다 불안정하다. 따라서 이번에도 **텍스트 기반 매칭을 그대로 유지**하고, 목업의 시간 기반 키는 참고하지 않는다 (명시적 설계 이탈, 사유 기록).

## 9. 에러 처리

- 라이브러리 패널의 SQLite 내보내기: 설정 패널과 동일한 try/catch + 버튼 텍스트 롤백 패턴.
- 클립보드 복사 실패(`navigator.clipboard` 미지원 컨텍스트 등): 조용히 무시, 사용자에게 별도 에러 표시하지 않음 (복사는 편의 기능이라 실패해도 핵심 흐름을 막지 않아야 함).
- 라이브러리 패널의 "▸ 시간" 시크: `adapter.seekTo`가 없거나 실패해도 조용히 무시 (기존 스크립트 패널의 시크 버튼과 동일한 관용도).

## 10. 테스트

이 저장소에는 `core/`용 자동화 JS 테스트 프레임워크가 없다 (기존 방침 유지). 순수 로직(필터 칩 조합 로직 등)은 Node 기반 즉석 검증 스크립트로 확인하고, DOM/`chrome.*` 연동 부분은 수동 체크리스트로 검증한다 (직전 브랜치와 동일한 패턴).

## 11. 범위 밖

- §1i의 "PANEL BEHAVIOR" 텍스트 컬럼 자체의 UI 구현 (개발 노트일 뿐, 실제 화면 아님)
- 자막 오버레이의 드래그/리사이즈 변경
- 스크립트 export 포맷 추가 (.srt/.txt)
- 라이브러리 패널에서의 단어/문장 삭제/편집 기능 (목업에 없음, 팝업이 원래 가지고 있었을 수 있는 삭제 기능은 이번에 라이브러리 패널로 이전하지 않음 — 필요 여부는 별도 논의)
