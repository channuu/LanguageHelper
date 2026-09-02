# 단어·표현 해설 데이터소스 설계

**날짜:** 2026-09-02
**상태:** 설계 완료, 구현 대기
**상위 문서:** `docs/superpowers/specs/2026-07-17-english-helper-design.md`

---

## 1. 배경

오버레이에서 단어를 클릭하면 뜨는 팝업은 지금 `api.dictionaryapi.dev`를 호출해
**영영 정의**를 보여준다(`core/word-popup.js:38`). 문장 쪽 "번역"은 번역기를 거친
값이 아니라 영상이 제공하는 모국어 자막 트랙을 그대로 옮겨 담은 것이다
(`core/script-panel.js:717`). 즉 지금 이 서비스에는 **해설이라 부를 만한 데이터소스가
없다.**

이 설계는 그 빈자리를 채운다. 목표는 두 가지다.

1. 단어의 **한국어 뜻과 품사**를 보여준다.
2. 단어 하나가 아니라 **구동사(phrasal verb)와 관용구 같은 다어절 표현**도 뜻을
   설명한다. 자막에서 실제로 학습자를 막아 세우는 것은 `find`나 `out`이 아니라
   `find out`이기 때문이다.

## 2. 데이터소스 결정

### 2.1 후보와 실측

설계 전에 후보 소스를 직접 호출해 커버리지를 측정했다.

**`api.dictionaryapi.dev` (현행)** — `look up`, `give up`은 200을 반환하지만
`run into`는 522, `get along with`는 없다. 무엇보다 **영영 정의만** 반환한다.
요구 1을 원천적으로 만족할 수 없어 탈락시킨다.

**en.wiktionary (kaikki.org wiktextract 추출)** — 구동사 표제어와 영영 정의는
충실하지만 한국어 번역이 희박하다.

| 표제어 | 영어 sense 수 | 한국어 번역 수 |
|---|---|---|
| look up | 6 | 1 |
| give up | 12 | 2 |
| take off | 12 | 2 |
| run into | 9 | 0 |
| come across | 8 | 0 |
| break down | 13 | 0 |
| put up with | 2 | 0 |
| heavy rain | 표제어 없음 | — |

**ko.wiktionary (한국어 위키낱말사전)** — 영어 표제어에 한국어 뜻이 직접 달려 있다.
예: `awkward` → "서투른, 미숙한 / 어색한, 자신이 없는 / 불편한 / 난처한, 골치거리의".

**LLM (Claude API)** — 세 요구를 모두 만족하는 유일한 후보였고, 문장 단위 호출
하나로 "표현 인식"과 "해설 생성"을 동시에 해결한다는 구조적 장점도 있었다. Firebase
Functions 프록시와 Blaze 요금제 전환이 전제였고, Haiku 4.5 기준 월 3,000문장에
약 3천 원으로 추산됐다. **비용을 지지 않는 쪽을 택해 이번 범위에서 제외한다.**
후속 스펙에서 다시 검토할 수 있다.

### 2.2 결정 — ko.wiktionary + en.wiktionary 병합

무료 두 소스를 병합했을 때의 실측 커버리지다.

| 대상 | ko.wiktionary | en.wiktionary 한국어 번역 | **합집합** |
|---|---|---|---|
| 일반 단어 30개 | 30/30 (100%) | — | **100%** |
| 구동사 60개 | 24/60 (40%) | 15/60 (25%) | **31/60 (52%)** |
| 연어 (`heavy rain` 등) | 표제어 없음 | 표제어 없음 | **0%** |

이 수치가 이 설계가 약속할 수 있는 것의 상한이다. 셋 다 그대로 받아들인다.

- **일반 단어의 한국어 뜻은 완전히 해결된다.** 현행 영영 정의보다 명백히 낫다.
- **구동사는 절반만 한국어 뜻이 나온다.** `find out`, `deal with`, `figure out`,
  `set up` 같은 빈출 표현이 빠진다. 나머지 절반은 **영영 정의로 폴백**한다.
  영영 정의는 en.wiktionary에 사실상 전부 있다.
- **연어는 다루지 않는다.** 어느 무료 사전에도 `heavy rain`, `make a decision` 류의
  표제어가 없다. 무료로 커버 가능한 다어절 표현은 **사전에 표제어로 등재된 구동사와
  관용구까지**이며, 이 설계의 "다어절 표현"은 그 범위를 뜻한다.

### 2.3 런타임에 위키 API를 부르지 않는 이유

MediaWiki `prop=extracts`는 **요청당 본문 1건**만 반환한다(`exlimit`을 올려도
`"exlimit" was too large for a whole article extracts request, lowered to 1` 경고와
함께 1건으로 깎인다). 자막 한 문장에서 표현 여러 개를 조회하면 왕복이 그 수만큼
늘어난다. 레이트리밋과 약관 문제도 따라온다.

따라서 **빌드 타임에 덤프를 가공해 정적 사전 파일을 만들고, 런타임은 그 파일만
읽는다.**

## 3. 범위

**포함:**
- 두 위키 덤프를 병합해 사전 아티팩트를 생성하는 빌드 스크립트
- 사전 아티팩트의 Firebase Hosting 배포와 버전 관리
- service worker의 사전 조회 계층 — IndexedDB 캐시 + Hosting fetch
- 자막 문장에서 구동사·관용구를 찾아내는 매칭 규칙
- 단어 팝업 개편 — 한국어 뜻·품사 표시, 다어절 표현 우선 표시
- `api.dictionaryapi.dev` 의존 제거

**제외 (범위 밖):**
- 연어(collocation) 해설 — §2.2
- 문맥에 맞는 의미 선택. 사전이 준 sense를 순서대로 보여줄 뿐, "이 장면에서는
  이 뜻"을 고르지 않는다. LLM 없이는 불가능하다
- 문법 구조 분석
- 문장 번역 API 도입. 문장의 한국어는 지금처럼 모국어 자막 트랙에서 온다
- 앱(Flutter) 측 변경 — §10 참고

## 4. 아키텍처

```
[빌드 타임 · 개발 PC · 수동 실행]
  kaikki English JSONL (3.2GB) ─┐
                                ├─→ tools/build-dictionary.js ─→ dist/dict/
  kowiktionary XML.bz2 (47MB)  ─┘

[배포]
  dist/dict/ ─→ firebase deploy --only hosting ─→ https://<project>.web.app/dict/

[런타임]
  content script                      service worker
  core/word-popup.js       ──메시지──→ background/service_worker.js
  core/subtitle-engine.js                ├─ lexicon/mwe-match.js  (문장 스캔)
                                         └─ lexicon/lookup.js
                                              ├─ IndexedDB   ← 대부분 여기서 끝
                                              └─ fetch → Hosting  (캐시에 없을 때만)
```

**조회는 전부 service worker가 한다.** 두 가지 이유다. 첫째, content script에서
직접 `fetch`하면 페이지의 CSP에 걸릴 수 있다. 둘째, `core/storage.js:31`이 이미
`chrome.runtime.sendMessage`로 service worker에 위임하는 패턴을 쓰고 있어 그것을
따른다.

**구동사 매칭도 service worker가 한다.** content script에 MWE 인덱스를 넘겨 로컬에서
스캔하면 왕복이 없어지지만, content script 파일들은 IIFE 전역 방식이라
(`manifest.json`의 `content_scripts.js` 목록) `node --test`로 단위 테스트할 수 없다.
service worker는 `"type": "module"`이라 `cloud/merge.js`처럼 순수 ESM 모듈을
import하고 그대로 테스트할 수 있다. 자막 cue는 수 초에 한 번 바뀌므로 메시지 왕복
비용은 문제가 되지 않는다.

## 5. 빌드 파이프라인 — `tools/build-dictionary.js`

Node 스크립트. 두 덤프를 스트리밍으로 읽어 `dist/dict/`를 생성한다. 수동 실행이며
CI에 넣지 않는다.

**입력**
- `https://kaikki.org/dictionary/English/kaikki.org-dictionary-English.jsonl` — 3.2GB,
  한 줄에 표제어 하나. `lang_code === "en"`인 항목만 취한다.
- `https://dumps.wikimedia.org/kowiktionary/latest/kowiktionary-latest-pages-articles.xml.bz2`
  — 47MB. 각 페이지 위키텍스트에서 `== 영어 ==` 섹션을 잘라 뜻줄을 뽑는다.

**출력 레코드**

```js
{
  "awkward": {
    pos: ["adj"],
    ko: ["서투른, 미숙한", "어색한, 자신이 없는", "불편한"],  // ko.wiktionary 우선, 없으면 en.wiktionary 번역
    en: ["Lacking dexterity or skill", "Not easily managed"],  // ko가 비었을 때의 폴백
    ipa: "ˈɔːkwəd",
    mwe: false
  }
}
```

- `ko`가 비어 있지 않으면 팝업은 `ko`만 보여준다. 비어 있을 때만 `en`으로 폴백한다.
- sense는 표제어당 **최대 4개**로 자른다. 자막을 보다 말고 읽는 팝업에 13개 sense는
  해가 된다.
- `mwe: true`인 표제어(공백 포함)는 별도로 `mwe-index.json`에도 실린다.

**어형 변화 처리** — kaikki 항목의 `forms` 필드에서 굴절형을 모아
`inflections.json`(`"gave" → "give"`)을 생성한다. 자막에는 `gave up`이 나오는데
표제어는 `give up`이므로 이 맵 없이는 매칭이 성립하지 않는다.

## 6. 배포 아티팩트

```
dist/dict/
  version.json        버전 + 버킷별 해시 (수백 바이트)
  mwe-index.json      다어절 표제어 문자열 목록
  inflections.json    굴절형 → 원형
  b/aw.json           버킷 — 표제어 앞 두 글자
  b/gi.json
  ...
```

**버킷팅** — 표제어를 소문자화한 뒤 앞 두 글자로 가른다(`give up` → `gi`). 한 글자
표제어와 비알파벳 시작 표제어는 `b/_.json`에 모은다. 사용자가 `awkward`를 클릭하면
`b/aw.json` 하나만 받으면 되고, 같은 대역의 이후 단어는 전부 캐시에서 나온다.

**`version.json`**

```json
{ "version": "2026-09-02", "buckets": { "aw": "3f2a…", "gi": "9c11…" } }
```

확장 시작 시 이 파일만 확인하고, 해시가 바뀐 버킷의 IndexedDB 항목만 버린다. **사전을
고쳐도 스토어 재심사가 필요 없다.**

**한도** — Hosting 무료 한도는 저장 10GB, 전송 360MB/일. 사전 전체가 압축 후 수십 MB
규모이고 사용자 1인당 실제 전송은 첫 사용 수 MB 수준이므로 Blaze 전환이 필요 없다.
`mwe-index.json`과 `inflections.json`은 통째로 받아야 하므로 이 둘의 크기가 첫 실행
체감을 결정한다 — §14.1.

**설정 변경**
- `firebase.json`에 `hosting` 블록 추가 (현재 `firestore` 항목만 있다)
- `manifest.json:9` `host_permissions`에 Hosting 도메인 추가,
  `https://api.dictionaryapi.dev/*` 제거
- `.gitignore`에 `dist/` 추가. 사전 아티팩트는 덤프에서 재생성되는 산출물이므로
  저장소에 넣지 않는다

## 7. 런타임

### 7.1 IndexedDB

DB `eh-dict`, store 두 개.

| store | key | value |
|---|---|---|
| `buckets` | 버킷 이름 (`"aw"`) | `{ hash, entries }` |
| `meta` | `"version"` / `"mwe"` / `"inflections"` | 각 파일 내용 |

`chrome.storage.local`을 쓰지 않는다. 그쪽은 학습 데이터의 영역이고, 사전은 언제든
버려도 되는 캐시라 성격이 다르다. 용량 제약도 IndexedDB 쪽이 여유롭다.

### 7.2 메시지 프로토콜

`background/service_worker.js`에 두 타입을 추가한다.

- `DICT_SCAN` — `{ text }` → `[{ term, start, end }]`
  자막 cue가 바뀔 때 `core/subtitle-engine.js`가 보낸다. 문장에 등장하는 다어절
  표현의 구간을 돌려준다.
- `DICT_LOOKUP` — `{ term }` → `{ pos, ko, en, ipa } | null`
  팝업이 뜰 때 `core/word-popup.js`가 보낸다.

### 7.3 조회 순서

1. `term`을 소문자화하고, `inflections`로 원형을 구한다
2. 해당 버킷이 IndexedDB에 있으면 거기서 답한다 — **네트워크 0**
3. 없으면 Hosting에서 버킷을 받아 IndexedDB에 넣고 답한다
4. 버킷에도 없으면 `null`

## 8. 다어절 표현 매칭 규칙

`lexicon/mwe-match.js`에 두는 **순수 함수**다. `chrome.*`도 `fetch`도 쓰지 않는다.

1. **정규화** — 소문자화, 문장부호 제거 후 토큰화. 각 토큰은 `inflections`로 원형화하되
   원형과 표층형을 **둘 다** 후보로 남긴다 (`gave` → `gave`, `give`)
2. **분리형 허용** — `look it up`, `gave the plan up`처럼 동사와 불변화사 사이에
   **최대 3토큰**까지 끼어드는 것을 허용한다. 그 이상은 우연의 일치일 가능성이 크다
3. **최장 일치 우선** — `put up with`가 잡히면 그 안의 `put up`은 버린다
4. **구간 겹침 금지** — 한 토큰은 하나의 표현에만 속한다. 앞에서 시작하는 것을
   우선한다
5. **`Used other than figuratively or idiomatically` 제외** — 이 문구로 시작하는
   sense는 축자적 용법을 가리키므로 빌드 타임에 버린다. 이게 남으면 `look up at the
   stars`가 구동사로 잡힌다

## 9. UI 변경 — `core/word-popup.js`

현재 팝업은 `fetchDefinition()`으로 매번 왕복하며 "불러오는 중…"을 띄운다. 새 구조에서는
대부분의 클릭이 IndexedDB에서 즉시 응답하므로 로딩 상태는 첫 조회에서만 스쳐 지나간다.

**표시 규칙**
- 클릭한 단어가 `DICT_SCAN`이 잡아낸 다어절 구간 안에 있으면 **그 표현을 먼저** 보여주고,
  단일 단어 뜻은 그 아래에 접어 둔다. `find out`을 클릭했는데 `find`의 뜻이 뜨면
  이 기능의 존재 이유가 사라진다
- `ko`가 있으면 한국어 뜻만, 없으면 영영 정의를 보여주고 **"한국어 뜻 없음"을 명시**한다.
  구동사의 48%가 여기에 해당하므로 숨기지 않고 드러낸다
- 품사와 IPA는 표제어 옆에 붙인다

**자막 오버레이** — `DICT_SCAN`이 돌려준 구간에 밑줄 등의 표시를 넣어 클릭 가능한
표현임을 알린다. 구체적 스타일은 구현 시 `ui/tokens.css`를 따른다.

## 10. 저장 데이터에 미치는 영향

`Storage.saveWord({ word, definition, ... })`(`core/storage.js:15`)의 `definition`에
이제 **한국어 뜻이 들어간다**. 필드 이름도 스키마도 그대로이므로 Firestore 동기화와
앱은 변경 없이 동작한다. 다만 앱의 플래시카드 뒷면에 뜨는 내용이 영영 정의에서
한국어 뜻으로 바뀐다 — **의도된 개선이며, 이번 스펙에서 앱 코드는 건드리지 않는다.**

다어절 표현을 저장할 때도 같은 `saveWord`를 쓴다. `word` 필드에 `"give up"`이 들어갈
뿐이다. 별도 타입을 만들지 않는다.

## 11. 에러 처리

| 상황 | 동작 |
|---|---|
| Hosting fetch 실패 (오프라인 등) | 팝업에 "사전을 불러오지 못했습니다" 표시. 저장 버튼은 그대로 동작 |
| `version.json` 조회 실패 | 기존 IndexedDB 캐시를 그대로 쓴다. 갱신 확인 실패가 조회 실패가 되어선 안 된다 |
| 버킷에 표제어 없음 | "정의를 찾을 수 없습니다" — 현행과 동일 |
| IndexedDB 쓰기 실패 | 조회 결과는 그대로 반환하고 캐시만 포기한다 |
| 첫 실행 + 오프라인 | 사전 없음. 이 방식이 감수하는 대가다 |

## 12. 테스트

`node --test test/**/*.js`. `cloud/merge.js`와 같이 **순수 함수만 테스트한다.**

- `test/mwe-match.test.js`
  - `gave up` → `give up` 매칭 (굴절형)
  - `look it up` → `look up` 매칭 (분리 1토큰)
  - `gave the whole plan up` → `give up` 매칭 (분리 3토큰)
  - 4토큰 이상 분리 → 매칭 안 됨
  - `put up with` 우선, 내부 `put up` 미검출 (최장 일치)
  - 겹치는 두 후보 중 앞선 것만 채택
- `test/build-dictionary.test.js`
  - kaikki 한 줄 → 레코드 변환, sense 4개 절단
  - ko.wiktionary 위키텍스트 → `== 영어 ==` 섹션 추출
  - 두 소스 병합 시 ko.wiktionary 우선
  - `Used other than figuratively` sense 제외
  - 버킷 배정 (`give up` → `gi`, `a` → `_`)

빌드 스크립트 본체(덤프 다운로드, 파일 쓰기)와 IndexedDB 계층은 자동 테스트하지 않는다.
후자는 확장을 실제로 로드해 육안 확인한다.

## 13. 라이선스

두 소스 모두 CC BY-SA다. 팝업 하단 또는 설정 패널에 출처와 라이선스를 표기한다.
파생 사전 데이터에도 동일 조건이 붙는다.

## 14. 미결 사항

1. **`mwe-index.json`과 `inflections.json`의 실제 크기.** 첫 실행에서 통째로 받는
   두 파일이라 첫 체감을 좌우한다. 빌드를 한 번 돌려 측정한 뒤, 너무 크면
   `inflections`를 불규칙 동사 위주로 추리거나 버킷과 함께 지연 로딩하는 안을 검토한다.
2. **버킷 두 글자가 적정한지.** 빈도가 몰리는 접두사(`co`, `pr`, `st`)의 버킷이
   과도하게 크면 세 글자로 쪼갠다. 측정 후 결정한다.
3. **사전 갱신 주기.** 수동 재빌드로 시작한다. 위키 덤프는 매달 갱신되지만 이 사전이
   그 속도를 따라갈 이유는 없다.
