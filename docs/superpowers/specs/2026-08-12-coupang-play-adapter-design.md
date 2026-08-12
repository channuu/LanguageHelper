# 쿠팡플레이 어댑터 설계

**날짜:** 2026-08-12
**상태:** 승인됨
**상위 문서:** `docs/superpowers/specs/2026-07-17-english-helper-design.md`

---

## 1. 배경

기존 `adapters/coupang.js`는 실제 쿠팡플레이 DOM 구조를 확인한 적 없이, 코드 주석에
"DOM 구조 확인 필요 — 아래는 일반적인 OTT 패턴"이라고 명시된 채로 CSS 셀렉터를
추측만 해둔 상태였다. Netflix/Disney+가 겪었던 것과 같은 문제(이중 자막이 실제로는
DOM에 동시에 존재하지 않음)를 그대로 안고 있었다.

## 2. 리서치 결과

크롬 웹스토어에 공개 배포된 이중자막 확장 프로그램("SecondSub", 쿠팡플레이/넷플릭스/
디즈니+/티빙 지원)의 코드를 직접 열어 확인한 결과, 쿠팡플레이는 YouTube/Netflix보다
훨씬 단순한 구조를 갖고 있다:

- `fetch`로 URL에 `/playback/play`가 포함된 요청의 JSON 응답에
  `data.raw.text_tracks[]`가 있고, **여기에 이미 모든 언어의 WebVTT 자막 URL이
  통째로 들어있다** — Netflix처럼 "모든 언어를 강제로 요청"하는 트릭이나 YouTube의
  pot 토큰 인증이 전혀 필요 없다.
- 트랙 필터링 조건: `kind === "subtitles" && mime_type === "text/webvtt"`
- 언어 코드는 `srclang`, 라벨은 `label`, URL은 `sources` 객체의 값들 중
  `src`가 `https`로 시작하는 것.
- 콘텐츠 ID는 URL의 UUID 패턴(`/play/<uuid>`)에서 추출.
- 비디오 엘리먼트는 평범한 `document.querySelector("video")` (Disney+처럼
  shadow DOM 안에 있지 않음).

## 3. 확인되지 않은 부분

쿠팡플레이 자체 자막을 화면에서 숨기는 정확한 CSS 셀렉터는 리서치로 확인하지
못했다 (참고한 확장 프로그램이 다른 방식을 쓰는 것으로 보임). Task 9(Disney+)와
동일하게 **일반적인 OTT 패턴으로 우선 구현하고, 실제 사이트에서 라이브 검증이
필요한 상태로 남긴다.**

## 4. 아키텍처 (Netflix와 동일한 패턴)

이미 검증된 `inject/netflix_inject.js` + `adapters/netflix.js` 구조를 그대로
따른다 — MAIN world에서 네트워크 요청을 가로채 실제 WebVTT 파일을 fetch하고,
isolated world의 어댑터가 그 결과를 받아 큐를 만든다.

### `inject/coupang_inject.js` (신규, MAIN world, `document_start`)

- `window.fetch`를 가로채서 URL에 `/playback/play`가 포함된 요청의 응답을
  가로채 `data.raw.text_tracks[]`를 파싱, `{videoId: [{code, description, url}]}`
  형태로 캐싱한다 (videoId는 응답을 가로챈 시점의 `location.href`에서
  UUID를 추출해서 키로 쓴다 — Netflix처럼 응답 바디에 movieId가 없으므로).
- `EH_CP_TRIGGER_LOAD` 메시지 수신 시, 캐시된 트랙 중 언어코드가 `en`으로
  시작하는 것과 `nativeLang`과 일치하는 것을 찾아 각각 fetch, `EH_CP_CAPTIONS_LOADED`로
  응답 (Netflix와 동일하게 `videoId` 포함해서 영상 전환 시 stale-response 방지).

### `adapters/coupang.js` (재작성)

- 기존 DOM 스크래핑 로직(`_getText`, `NATIVE_SELECTORS`, MutationObserver 기반
  자막 읽기) 전면 제거.
- `_getContentId()` — `location.pathname`에서 UUID 패턴 매칭으로 콘텐츠 ID 추출.
- `_parseVtt()` — Netflix 어댑터의 파서를 그대로 재사용 (표준 WebVTT, 병합 불필요).
- `_getCueAtTime()` — Netflix와 동일한 이진 탐색.
- `_hideNativeSubtitles()` — 확인되지 않은 셀렉터로 우선 구현, 라이브 검증 필요로 표시.
- 영상 전환 감지는 URL 변화 기반 MutationObserver (Netflix와 동일 패턴).

### `manifest.json`

- `inject/coupang_inject.js`를 `https://*.coupangplay.com/*`에 MAIN world,
  `document_start`로 등록.
- `web_accessible_resources`에 추가 (기존 `page_script.js`/`netflix_inject.js`와
  동일 패턴).

## 5. 데이터 흐름

1. 페이지 로드 시 MAIN world 스크립트가 `fetch`를 가로채기 시작.
2. 쿠팡플레이 플레이어가 `/playback/play` API를 호출하면 응답에서 트랙 캡처.
3. 어댑터가 초기화되면서 (또는 영상 전환 시) `EH_CP_TRIGGER_LOAD` 발송.
4. MAIN world 스크립트가 캐시된 트랙에서 영어/모국어 URL을 찾아 각각 fetch.
5. 두 자막을 파싱해서 `EH_CP_CAPTIONS_LOADED`로 어댑터에 전달 (videoId 포함).
6. 어댑터는 현재 콘텐츠 ID와 일치할 때만 큐를 갱신 (stale-response 방지).

## 6. 테스트 계획

- WebVTT 파서는 Netflix 어댑터와 동일 로직이므로 재검증 불필요.
- 트랙 파싱 로직(`text_tracks` → `{code, url}` 매핑, https 소스 필터링)에 대한
  헤드리스 Chrome 시뮬레이션 검증 — 이전 Netflix/YouTube 작업과 동일한 방식.
- **실제 쿠팡플레이 계정으로 라이브 검증 필요** — 이 환경엔 계정이 없어 로직만
  검증 가능. 특히 `_hideNativeSubtitles()`의 셀렉터가 실제로 맞는지 확인 필요.

## 7. 범위 밖

- 쿠팡플레이 자체 자막 스타일링(폰트 크기, 위치 등) 커스터마이징
- 트랙이 하나도 없는 콘텐츠(자막 미제공)에 대한 안내 UI
