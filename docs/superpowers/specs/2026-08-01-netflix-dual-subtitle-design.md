# Netflix 이중 자막 재설계

## 배경

기존 `adapters/netflix.js`(Phase A Task 8)는 "Netflix가 영어/한국어 자막을 별도 DOM 요소로
동시에 렌더링한다"는 잘못된 전제로 작성됐다. 실제 Netflix 웹 플레이어는 **한 번에 하나의
자막 트랙만** DOM에 렌더링하므로, 기존 `NATIVE_SELECTORS`(`:not([lang="en"])`)는 항상
빈 문자열을 반환하고 이중 자막은 동작하지 않는다.

## 접근 방식

YouTube 어댑터(`inject/page_script.js` + `adapters/youtube.js`)와 동일한 패턴을 따른다:
MAIN world에서 네트워크 요청을 가로채 실제 자막 파일(WebVTT)을 양쪽 언어로 fetch하고,
isolated world의 어댑터는 그 결과를 받아 큐를 만든다.

오픈소스 Netflix Subtitle Downloader(Greasyfork)를 참고해 검증된 메커니즘을 사용한다:

1. Netflix는 플레이어 manifest 요청 바디에 `showAllSubDubTracks: true`와 지원 포맷
   프로필(`webvtt-lssdh-ios8`)이 포함되어야 응답에 **모든 언어**의 자막 다운로드 URL을
   내려준다 (기본값은 현재 선택된 언어만).
2. `window.fetch`/`XMLHttpRequest.send`가 manifest 요청 바디를 만들 때 쓰는
   `JSON.stringify`를 가로채서, `url`이 `manifest`/`licensedManifest`를 포함하는
   요청의 바디에 `showAllSubDubTracks=true`와 `webvtt-lssdh-ios8` 프로필을 주입한다.
3. manifest 응답의 `JSON.parse`를 가로채서 `result.timedtexttracks`(트랙 배열: language,
   rawTrackType, ttDownloadables[format].downloadUrls)를 추출한다.
4. 영어 트랙(`language==='en'`, `rawTrackType==='subtitles'` 우선)과 네이티브 트랙을
   골라 `ttDownloadables['webvtt-lssdh-ios8'].downloadUrls`의 URL 중 하나를 fetch,
   WebVTT 텍스트를 파싱해 `{start, end, text}` 큐 배열로 변환한다.
5. 결과를 `postMessage`로 isolated world 어댑터에 전달한다.

## 컴포넌트

- **`inject/netflix_inject.js`** (신규, MAIN world, `document_start`)
  - JSON.stringify/parse 후킹 (Netflix subtitle downloader와 동일 메커니즘)
  - `EH_NF_TRIGGER_LOAD` 메시지 수신 시 캐시된 트랙에서 언어 선택 → WebVTT fetch →
    `EH_NF_CAPTIONS_LOADED` 응답
  - `movieId`를 포함해 늦게 도착한 이전 영상 응답을 어댑터가 걸러낼 수 있게 한다
    (YouTube 어댑터를 고치며 확인한 stale-response 문제를 처음부터 방지)

- **`adapters/netflix.js`** (재작성)
  - DOM 스크래핑 로직(`_getText`, `NATIVE_SELECTORS`, MutationObserver 기반 자막 읽기) 제거
  - `getSubtitleTracks()`/`onTracksReady()`가 실제 큐 배열을 반환하도록 변경 (YouTube와
    동일하게 스크립트 패널에서 전체 스크립트 열람 가능)
  - 기존 `_hideNativeSubtitles()`(Netflix 자체 자막 DOM 숨김)는 유지
  - RAF 기반 `onSubtitleChange`로 전환 (YouTube의 `_getCueAtTime` 이진 탐색과 동일 패턴)
  - SPA 라우팅 감지(영상 변경) 로직은 기존 것을 유지하되, 영상 전환 시 새 movieId로
    `EH_NF_TRIGGER_LOAD` 재요청

- **`manifest.json`**
  - `inject/netflix_inject.js`를 `https://www.netflix.com/*`에 MAIN world,
    `document_start`로 추가 (YouTube 항목과 동일한 형태)
  - `web_accessible_resources`에 항목 추가

## WebVTT 파싱

Netflix의 `webvtt-lssdh-ios8` 포맷은 표준 WebVTT(`WEBVTT` 헤더, `HH:MM:SS.mmm -->
HH:MM:SS.mmm` 타임스탬프, 그 다음 줄에 텍스트, 빈 줄로 큐 구분)이므로 표준 WebVTT
파서를 새로 작성한다 (YouTube의 XML/json3 파서와는 포맷이 다르므로 공유 불가).
텍스트 내 `<c>`, `<i>` 등 스타일링 태그와 위치 지정 cue setting은 제거하고 순수 텍스트만
남긴다.

## 범위 밖

- 다른 자막 포맷(DFXP/IMSC1.1)은 지원하지 않는다 — WebVTT가 항상 사용 가능하면 그것만 사용.
- `showAllSubDubTracks` 강제가 막힐 경우(Netflix 정책 변경)의 폴백은 이번 범위에 넣지
  않는다 — 실패 시 패널에 "자막 없음"이 뜨는 기존 동작으로 충분하다.
