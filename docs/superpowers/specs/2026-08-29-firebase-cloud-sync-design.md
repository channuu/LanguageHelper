# Firebase 계정 + 클라우드 동기화 설계 (Phase C 1단계)

**날짜:** 2026-08-29
**상태:** 설계 완료, 구현 대기
**상위 문서:** `docs/superpowers/specs/2026-07-17-english-helper-design.md` §5 (Phase C)

---

## 1. 배경

지금 확장과 앱 사이에 학습 데이터를 옮기는 유일한 경로는 수동이다. 확장에서
`.sqlite` 파일을 내려받고, 앱의 "가져오기" 화면에서 그 파일을 직접 골라야 한다.
영상을 보며 단어를 저장하는 행위와 그것을 복습하는 행위 사이에 파일 관리라는
단계가 끼어 있어, 실제로는 대부분의 저장 항목이 앱까지 도달하지 못한다.

이번 작업은 그 왕복을 없앤다. 계정 하나로 확장과 앱을 묶고, 저장한 단어가 별도
조작 없이 앱에 나타나게 한다.

Phase C 표(§5)에 적힌 항목 중 **인증과 데이터 저장만** 다룬다. Claude API 연동,
복습 알고리즘 교체, 인앱결제는 이후 별도 스펙이다.

## 2. 범위

**포함:**
- Firebase Authentication 이메일/비밀번호 로그인 — 확장, 앱 양쪽
- Firestore를 통한 `words` / `sentences` / `study_sessions` / `weekly_goals` 동기화
- 확장: 단어·문장 저장에 로그인을 요구 (자막·스크립트 기능은 로그인 없이 유지)
- 앱: 로그인 게이트 — 미로그인 시 앱 사용 불가
- 기존 로컬 데이터 1회 자동 업로드 마이그레이션
- `.sqlite` 내보내기/가져오기 기능 **완전 제거**, JSON 내보내기로 대체
- 앱 하단 네비게이션 4탭화, 설정 화면에 계정 항목 추가

**제외 (범위 밖):**
- Google / Apple 소셜 로그인 — 이메일/비밀번호만
- 자막 오버레이 설정(글꼴 크기, 프리셋, `cueLines` 등)의 동기화 — 기기별 설정으로 남긴다
- 앱의 `active_session_state`(진행 중인 타이머 세션, `shared_preferences`) 동기화 —
  기기에 묶인 휘발성 상태다
- 비밀번호 재설정 이메일, 이메일 주소 인증 — §10.4 참고
- Claude API, 인앱결제, 복습 알고리즘 변경
- 실시간 리스너 기반 동기화

---

## 3. 아키텍처 — 로컬이 진실, 클라우드는 미러

### 3.1 상위 스펙과의 차이

`2026-07-17-english-helper-design.md` §4.3은 Phase C에서 `CloudRepository`가
`LearningRepository`를 구현하도록 **교체**하는 방식을 전제했다. 이번 설계는 그
방식을 쓰지 않는다.

교체 방식이면 저장 동작이 네트워크 왕복에 묶인다. 그런데 확장에서 단어를 저장하는
순간은 정확히 "네트워크를 기다리면 안 되는 순간"이다. 앱의 `cloud_firestore`는
오프라인 캐시가 내장돼 있어 그럭저럭 버티지만, 확장은 REST로 붙기 때문에(§4.1)
그런 캐시가 없다. 연결이 끊긴 상태에서 저장하면 항목이 그대로 유실된다.

따라서 **`chrome.storage.local`과 `LocalSQLiteRepository`를 진실의 원천으로 그대로
두고, 그 위에서 도는 동기화 계층을 새로 얹는다.** 화면 코드가 저장소를 호출하는
방식은 바뀌지 않는다.

이 선택의 대가는 명확하다. `updated_at` 추가, 삭제 큐, 로컬/원격 두 상태를 맞추는
로직이 전부 직접 작성할 코드가 된다. 교체 방식이었다면 Firestore SDK 안에 숨었을
부분이다. 확장이 학습 데이터가 들어오는 유일한 입구라는 점을 감안해 이 비용을
받아들인다.

### 3.2 구성

```
[확장]                            [Firestore]              [앱]
core/storage.js                                            LocalSQLiteRepository (변경 없음)
  ↓ SAVE_WORD                    users/{uid}/                      ↑
background/service_worker.js       words/{id}             sync/sync_service.dart  ← 신규
  ├→ chrome.storage.local (진실)   sentences/{id}          sync/auth_service.dart ← 신규
  └→ cloud/sync.js  ←── 신규 ───   study_sessions/{id}       └ firebase_auth
       ├ cloud/auth.js             weekly_goals/{id}          └ cloud_firestore
       └ cloud/firestore-rest.js
```

**확장 신규 파일** — 서비스워커에서만 로드한다. 콘텐츠 스크립트에는 넣지 않는다.
인증 토큰이 영상 페이지의 DOM 컨텍스트에 노출될 이유가 없다.

| 파일 | 책임 | 의존 |
|---|---|---|
| `cloud/config.js` | Firebase 프로젝트 설정값 | 없음 |
| `cloud/firestore-rest.js` | REST 값 타입 래핑/언래핑, 문서 쓰기·삭제, 컬렉션 읽기 | `fetch` |
| `cloud/auth.js` | 회원가입, 로그인, 토큰 갱신, 토큰 보관 | `chrome.storage`, `fetch` |
| `cloud/sync.js` | push / pull / LWW 병합 | 위 셋 |
| `auth/login.html`, `auth/login.js` | 확장 로그인 페이지 | `cloud/auth.js` |

`firestore-rest.js`만 REST 표현을 안다. 그 위 계층은 평범한 JS 객체만 다룬다.
`sync.js`의 병합 판정은 `chrome.*`을 호출하지 않는 순수 함수로 분리해 Node에서
직접 테스트한다(§12).

서비스워커는 `manifest.json`에서 `"type": "module"`로 전환하고 위 파일들을 ES
모듈로 `import`한다. 지금의 무빌드 구조를 유지하면서 콘텐츠 스크립트의 IIFE +
`window.EH` 패턴을 서비스워커까지 끌고 가지 않기 위해서다(워커에는 `window`가
없다).

**앱 신규 파일**

| 파일 | 책임 |
|---|---|
| `mobile/lib/data/sync/auth_service.dart` | `firebase_auth` 래핑, 인증 상태 스트림 |
| `mobile/lib/data/sync/sync_service.dart` | push / pull / LWW 병합 |
| `mobile/lib/features/auth/login_screen.dart` | 로그인·회원가입 화면 |
| `mobile/lib/features/auth/auth_gate.dart` | 인증 상태에 따라 로그인 화면 ↔ `AppShell` 분기 |

`sync_service.dart`는 `LearningRepository`와 `StudyTimerRepository` 양쪽을 주입받아
쓴다. 두 저장소를 하나로 합치지 않는다.

**앱 신규 의존성** — `pubspec.yaml`에 `firebase_core`, `firebase_auth`,
`cloud_firestore`를 추가하고 `file_picker`를 제거한다(§8). FlutterFire CLI로
`mobile/lib/firebase_options.dart`를 생성하고, iOS는 `GoogleService-Info.plist`를
`mobile/ios/Runner/`에 추가한다.

---

## 4. 인증

### 4.1 확장 — REST 직접 호출

확장은 Firebase JS SDK를 번들하지 않는다. 이 저장소에는 빌드 스텝이 없고, SDK를
쓰려면 번들러 도입이 강제된다. 이메일/비밀번호 방식은 OAuth 리다이렉트가 없어
REST 호출 몇 개로 끝나므로 SDK가 주는 이득이 변환 코드 100줄 남짓에 불과하다.

| 동작 | 엔드포인트 |
|---|---|
| 회원가입 | `POST identitytoolkit.googleapis.com/v1/accounts:signUp?key={apiKey}` |
| 로그인 | `POST identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key={apiKey}` |
| 토큰 갱신 | `POST securetoken.googleapis.com/v1/token?key={apiKey}` (`grant_type=refresh_token`) |
| Firestore | `Authorization: Bearer {idToken}` 헤더 (API 키 불필요) |

`manifest.json`의 `host_permissions`에 `identitytoolkit.googleapis.com`,
`securetoken.googleapis.com`, `firestore.googleapis.com`을 추가한다.

토큰은 `chrome.storage.local`에 `eh-auth` 키로 보관한다:
`{ uid, email, idToken, refreshToken, expiresAt }`.

### 4.2 확장 — 비밀번호 입력 위치

**로그인 폼은 확장 자체 페이지에서만 띄운다.** 오버레이 안(콘텐츠 스크립트)에 두면
YouTube·Netflix 페이지의 스크립트가 비밀번호 입력란을 읽을 수 있다. 콘텐츠
스크립트는 JS 컨텍스트만 격리될 뿐 DOM은 호스트 페이지와 공유하기 때문이다.

흐름:

1. 오버레이에서 저장 버튼 클릭 → 미로그인이면 "로그인이 필요해요" 토스트 +
   "로그인" 버튼
2. 버튼 → 서비스워커에 `EH_OPEN_LOGIN` 메시지 → `chrome.tabs.create`로
   `chrome.runtime.getURL('auth/login.html')` 새 탭
3. 로그인 성공 → 서비스워커가 지원 플랫폼 탭들에 `EH_AUTH_CHANGED` 브로드캐스트 →
   오버레이가 저장 버튼을 활성 상태로 갱신

이미 `EH_EXPORT_PRINT`가 확장 페이지를 새 탭으로 여는 패턴을 쓰고 있으므로 새로운
구조가 아니다.

### 4.3 앱 — 로그인 게이트

`main.dart`가 `AuthGate`를 최상위에 둔다. `AuthService`의 인증 상태 스트림을 보고
미로그인이면 `LoginScreen`, 로그인이면 기존 `AppShell`을 띄운다. 앱 시작 시
`firebase_auth`가 저장된 세션을 복원하므로 매번 로그인할 필요는 없다.

`LoginScreen`은 로그인/회원가입을 탭 하나로 전환하는 단일 화면이다.

### 4.4 로그아웃과 계정 전환

로그인이 필수인 모델에서 로그아웃은 곧 데이터 접근 권한 없음을 뜻한다. 따라서
**사용자가 명시적으로 로그아웃하면 로컬 캐시를 비운다.** 재로그인하면 pull로
복구된다.

다만 아직 안 올라간 항목이 있으면 그대로 유실되므로, 로그아웃은 다음 순서를 지킨다:

1. 미동기 항목을 먼저 밀어낸다
2. 전부 성공 → 로컬 캐시를 비우고 `eh-auth` 삭제
3. 실패한 항목이 있음 → "{n}개 항목이 아직 저장되지 않았어요. 로그아웃하면
   사라집니다" 확인 다이얼로그. 사용자가 확인해야만 진행한다

**계정 전환**도 같은 사고를 낳는다. 로컬에 마지막 `uid`를 기록해 두고, 로그인한
`uid`가 다르면 로컬 캐시를 비운 뒤 pull한다. B 계정이 A 계정의 단어를 보는 일을
막는다.

**토큰 갱신 실패로 인한 강제 로그아웃은 다르다**(§7.4). 사용자 의사가 아니므로
**로컬 캐시를 비우지 않는다.** 미동기 항목이 남아 있을 수 있다.

---

## 5. 로그인이 필요한 기능 경계

| 로그인 없이 사용 가능 | 로그인 필요 |
|---|---|
| 자막 오버레이, 이중 자막 | 단어 저장 |
| 스크립트 패널 — 검색, 자동 스크롤 | 문장 저장 |
| 스크립트 HTML/PDF 내보내기 | 라이브러리(저장 목록) 패널 |
| 설정 패널 전체 | |

앱은 로그인 없이 아무것도 못 한다.

미로그인 상태에서 라이브러리 패널을 열면 목록 대신 로그인 안내와 버튼을 보여준다.
단어 팝업의 저장 버튼은 비활성 처리하지 않고 평소대로 두되, 누르면 §4.2의 로그인
유도 흐름을 탄다 — 비활성 버튼은 이유를 설명하지 못한다.

**강제 지점은 서비스워커다.** UI에서 막는 것과 별개로 `SAVE_WORD`,
`SAVE_SENTENCE`, `GET_ALL`, `DELETE_ITEM` 핸들러가 `eh-auth` 부재 시
`{ success: false, error: 'auth_required' }`를 반환한다. 콘텐츠 스크립트는 호스트
페이지와 DOM을 공유하므로 UI 조건만으로는 경계가 되지 못한다.

---

## 6. 데이터 모델

### 6.1 Firestore 구조

```
users/{uid}/words/{id}
users/{uid}/sentences/{id}
users/{uid}/study_sessions/{id}
users/{uid}/weekly_goals/{id}
```

**문서 id는 기존 UUID를 그대로 쓴다.** 확장과 앱이 이미 같은 방식으로 UUID를
발급하므로, 병합이 id 합집합으로 환원되고 같은 항목이 중복 생성될 여지가 없다.

**필드명은 snake_case로 통일한다.** 현재 확장은 camelCase(`savedAt`), 앱 SQLite는
snake_case(`saved_at`)로 서로 다르다. snake_case를 택하면 앱 모델의 `fromMap`이
거의 그대로 재사용되고, 확장 쪽 변환 규칙도 제거될 `core/sqlite-export.js`가 이미
쓰던 것과 동일해 새로 발명할 매핑이 아니다.

### 6.2 추가 필드

4개 컬렉션 공통으로 두 필드를 추가한다:

| 필드 | 타입 | 의미 |
|---|---|---|
| `updated_at` | ISO8601 문자열 | 마지막 변경 시각. LWW 판정 기준 |
| `synced_at` | ISO8601 문자열 \| null | 마지막으로 서버에 반영된 시각 |

`saved_at`은 생성 시각이라 복습해도 바뀌지 않으므로 LWW 기준이 될 수 없다.
`synced_at == null`이면 아직 안 올라간 항목이다.

두 필드 모두 로컬 스키마(확장 `chrome.storage` 항목, 앱 SQLite 컬럼)에 추가한다.
**Firestore 문서에 올라가는 것은 `updated_at`뿐이다.** `synced_at`은 "이 기기가
언제 올렸는가"라는 기기별 사실이라 서버에 둘 의미가 없고, 서버에 두면 기기끼리
서로의 값을 덮어쓴다.

### 6.3 삭제 큐

삭제는 행이 사라지므로 `updated_at`으로 표현할 수 없다. 양쪽에 같은 모양의 큐를
둔다:

- 앱: `sync_queue(entity TEXT, doc_id TEXT)` 테이블
- 확장: `chrome.storage.local`의 `eh-sync-queue` 배열 — `[{ entity, docId }]`

서버 삭제에 성공하면 큐에서 제거한다. upsert는 `synced_at`으로 충분하므로 큐에
넣지 않는다.

### 6.4 마이그레이션

**앱** — DB 버전 3 → 4. `words`, `sentences`, `study_sessions`, `weekly_goals`
네 테이블에 `updated_at`, `synced_at` 컬럼을 추가하고 `sync_queue` 테이블을
생성한다. 기존 행은 `updated_at = saved_at`(타이머 테이블은 `created_at` 또는
`started_at`), `synced_at = NULL`로 채운다. 이렇게 하면 **마이그레이션 자체가 곧
"기존 데이터 전량 업로드 대상" 표시**가 된다.

**확장** — 스키마 버전이 없으므로 서비스워커 시작 시 `eh-words`/`eh-sentences`의
각 항목에 `updated_at`이 없으면 `savedAt` 값으로 채우고 `synced_at`을 `null`로
둔다. 필드명도 이때 snake_case로 바꾼다. 한 번 수행 후 `eh-schema-version` 키에
기록해 반복하지 않는다.

로그인이 필수가 된 이후로는 "로그인 전에 쌓인 로컬 데이터"가 생길 수 없으므로,
양방향 병합은 이 1회 마이그레이션에서만 의미가 있다.

---

## 7. 동기화 흐름

### 7.1 푸시

1. 저장/수정/삭제 → **로컬에 먼저 반영**하고 `updated_at = now`, `synced_at = null`
   (삭제는 `sync_queue`에 기록)
2. 곧바로 Firestore에 쓰기를 시도 → 성공하면 `synced_at` 갱신, 삭제는 큐에서 제거
3. 실패해도 UI는 성공으로 처리한다. 항목은 미동기 상태로 남는다

재시도는 **다음 쓰기가 일어날 때 밀린 것까지 함께** 밀어낸다. 확장은 서비스워커가
수시로 종료되므로 여기에 더해 `chrome.alarms`로 15분 주기 flush를 건다. 앱은
포그라운드 복귀 시 밀어낸다.

### 7.2 풀

| | 시점 | 범위 |
|---|---|---|
| 확장 | 서비스워커 시작 시, 라이브러리 패널 열 때 | `updated_at` 내림차순 500개 |
| 앱 | 앱 시작 시, 포그라운드 복귀 시 | 전체 |

확장의 500개 제한은 현재 서비스워커가 `chrome.storage`에 최근 500개만 남기는 동작을
그대로 이어받은 것이다. 서버가 진실이 된 이상 확장의 로컬은 "최근 500개 뷰"로
해석하면 되고, 잘린 항목은 앱에서 전부 볼 수 있다.

### 7.3 병합 규칙

받아온 문서 집합과 로컬을 맞출 때:

1. **`synced_at == null`인 로컬 항목은 건드리지 않는다.** 아직 안 올라간 항목이
   서버에 없는 것은 당연한데, "서버에 없으면 삭제"를 그대로 적용하면 방금 저장한
   단어가 사라진다
2. 양쪽에 있으면 `updated_at`이 큰 쪽을 **통째로** 채택한다. 같으면 서버 쪽을
   쓴다 — 기기 시계 오차로 두 기기가 서로를 무한히 덮어쓰는 것을 막는다
3. 서버에만 있으면 로컬에 삽입한다
4. 로컬에만 있고 `synced_at != null`이면 다른 기기에서 삭제된 것이므로 로컬에서도
   지운다

4번이 삭제 전파를 담당한다. 전체(또는 최근 500개) 집합을 받아 비교하므로 tombstone
문서가 필요 없다.

### 7.4 토큰 갱신

`idToken`은 1시간 만료다. 요청이 401로 실패하면 `refreshToken`으로 갱신하고 **딱
한 번** 재시도한다. 갱신까지 실패하면(비밀번호 변경, 계정 삭제 등) 로그아웃 상태로
전환하고 재로그인을 요구하되, §4.4에 따라 로컬 캐시는 비우지 않는다.

### 7.5 동기화 상태 표시

확장 라이브러리 패널 헤더와 앱 설정 화면의 계정 항목에 마지막 동기화 시각을
표시하고, 미동기 항목이 있으면 개수를 함께 보여준다. 푸시 실패를 조용히 삼키는
설계이므로, 사용자가 "올라갔나?"를 확인할 수 있는 유일한 창구다.

---

## 8. `.sqlite` 내보내기 제거

클라우드 동기화가 파일 왕복을 대체하므로 `.sqlite` 경로를 완전히 제거한다.

**확장에서 제거:**
- `core/sqlite-export.js`
- `vendor/sql-wasm.js`, `vendor/sql-wasm.wasm`
- `manifest.json` — 4개 플랫폼 `content_scripts`의 `vendor/sql-wasm.js` 항목,
  `web_accessible_resources`의 `vendor/sql-wasm.wasm` 항목
- `core/settings-panel.js:127`, `core/library-panel.js:81`의 내보내기 호출

`vendor/sql-wasm.js`는 지금 4개 플랫폼 모든 페이지의 콘텐츠 스크립트에 포함돼 있어,
내보내기를 한 번도 쓰지 않는 사용자도 매 페이지에서 48KB를 파싱하고 있다. 제거로
가장 크게 절약되는 부분이다.

**앱에서 제거:**
- `mobile/lib/features/import/` 전체
- `repository.dart`의 `mergeFromFile`, `MergeResult`,
  `InvalidBackupFileException`, `getLastImportSummary`
- `mobile/lib/data/models/last_import_summary.dart`
- `mobile/test/features/import/import_screen_test.dart` 및
  `repository_test.dart`의 관련 케이스
- `pubspec.yaml`의 `file_picker` 의존성

**루트 정리:** `firebase-config.js`(구식 프로토타입)를 삭제하고 실제 설정값은
`cloud/config.js`에 둔다. `flutter_integration.dart`도 삭제한다 — Phase B 스펙이
이미 "구식 프로토타입"으로 규정했고 어디서도 참조되지 않는다. `README.md`의 해당
설명도 갱신한다.

**남는 것:** 스크립트 HTML/PDF 내보내기(`export/print.html`,
`core/script-panel.js`의 `exportScript`)는 별개 기능이므로 그대로 둔다.

---

## 9. UI 변경

### 9.1 확장

- **`auth/login.html` 신규** — 이메일, 비밀번호, 로그인/회원가입 전환. `ui/tokens.css`
  를 재사용해 확장의 기존 시각 언어를 따른다
- **라이브러리 패널** — 미로그인이면 목록 대신 로그인 안내. 로그인 상태면 헤더에
  마지막 동기화 시각과 미동기 개수, 계정 이메일과 로그아웃
- **설정 패널** — `.sqlite` 내보내기 행 제거

### 9.2 앱

- **하단 네비게이션 4탭화** — 홈 / 플래시카드 / 타이머 / 설정.
  `app_bottom_nav.dart`의 `_labels`에서 "가져오기" 제거, `_ImportIconPainter` 삭제,
  `app.dart`의 화면 목록에서 `ImportScreen` 제거. 목업 `AppNav.dc.html`이 5탭이므로
  목업 갱신이 필요하다
- **`login_screen.dart` 신규** — 앱 테마(`app_theme.dart`)를 따른다
- **설정 화면에 계정 섹션 추가** — 로그인한 이메일, 마지막 동기화 시각, "지금
  동기화", "로그아웃"
- **설정 화면에 "내 데이터 내보내기(JSON)" 추가** — `words`/`sentences`/
  `study_sessions`/`weekly_goals`를 단일 JSON 파일로 저장·공유한다. 계정을 지우면
  데이터가 함께 사라지므로, 사용자가 자기 데이터를 가져갈 최소한의 수단을 남긴다.
  `.sqlite` 내보내기와 달리 추가 의존성이 필요 없다
- **설정 화면의 "DB 파일 경로" 행 제거** — 파일을 직접 다룰 이유가 없어졌다

---

## 10. 에러 처리

### 10.1 인증

| 상황 | 처리 |
|---|---|
| `EMAIL_EXISTS` | "이미 가입된 이메일이에요" |
| `EMAIL_NOT_FOUND`, `INVALID_PASSWORD`, `INVALID_LOGIN_CREDENTIALS` | "이메일 또는 비밀번호가 맞지 않아요" — 어느 쪽이 틀렸는지 구분해 알려주지 않는다 |
| `WEAK_PASSWORD` | "비밀번호는 6자 이상이어야 해요" |
| `TOO_MANY_ATTEMPTS_TRY_LATER` | "잠시 후 다시 시도해 주세요" |
| 네트워크 실패 | "연결을 확인해 주세요" + 재시도 버튼 |

### 10.2 동기화

푸시 실패는 사용자에게 알리지 않는다. 로컬 저장은 이미 성공했고, 매번 토스트를
띄우면 지하철에서 단어를 저장할 때마다 경고가 뜬다. 대신 §7.5의 미동기 개수로
드러낸다.

풀 실패는 명시적 동기화(설정 화면의 "지금 동기화")일 때만 토스트를 띄운다. 자동
풀 실패는 조용히 넘어가고 다음 시점에 재시도한다.

### 10.3 Firestore 할당량 초과

Spark 무료 요금제의 일일 읽기/쓰기 한도를 넘으면 `RESOURCE_EXHAUSTED`가 온다.
동기화만 멈추고 로컬 학습은 계속되므로, 미동기 개수 표시 외에 별도 처리는 하지
않는다.

### 10.4 비밀번호를 잊은 경우

이번 범위에서는 재설정 흐름을 만들지 않는다. 로그인 화면에 "비밀번호를
잊으셨나요?" 링크를 두지 않는다 — 눌러도 아무것도 못 하는 링크보다 없는 편이 낫다.
재설정 이메일 발송(`accounts:sendOobCode`)은 다음 스펙에서 다룬다.

---

## 11. 보안 규칙과 설정값

### 11.1 Firestore 보안 규칙

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{uid}/{document=**} {
      allow read, write: if request.auth != null && request.auth.uid == uid;
    }
  }
}
```

`firestore.rules`로 저장소에 커밋한다.

### 11.2 설정값 관리

Firebase Web API 키는 **비밀이 아니다.** 클라이언트에 노출되는 것을 전제로 설계된
식별자이며, 실제 접근 통제는 §11.1의 보안 규칙이 담당한다. 따라서 `cloud/config.js`
와 앱의 `firebase_options.dart`를 저장소에 커밋한다. `.gitignore`의
`# firebase-config.js` 주석 줄은 제거한다 — 잘못된 전제를 남겨두면 다음 사람이
헷갈린다.

Firestore 규칙이 배포되지 않은 상태에서는 데이터가 무방비이므로, **규칙 배포가
클라이언트 릴리스보다 먼저**여야 한다.

---

## 12. 테스트

**확장** — 지금 JS 테스트 하네스가 없다. 의존성 없이 Node 내장 `node --test`를
도입하고, `chrome.*`이나 DOM에 접근하지 않는 순수 모듈만 대상으로 한다:

- `cloud/firestore-rest.js` — 값 타입 래핑/언래핑 왕복
- `cloud/sync.js`의 병합 함수 — §7.3의 4개 규칙 각각, 특히 (1) 미동기 항목 보존과
  (4) 삭제 전파

`fetch`와 `chrome.storage`에 의존하는 부분은 수동 검증한다.

**앱** — 기존 `mobile/test` 구조를 따른다.

- `sync_service_test.dart` — 가짜 Firestore와 인메모리 저장소로 §7.3 병합 규칙,
  §4.4 계정 전환 시 캐시 비우기
- DB 버전 3 → 4 마이그레이션 — 기존 데이터가 든 v3 DB를 열어 `updated_at`이
  `saved_at`으로 채워지고 `synced_at`이 `NULL`인지 확인
- `login_screen_test.dart` — 입력 검증과 §10.1 에러 메시지 매핑
- `settings_screen_test.dart` — 계정 섹션 추가, 가져오기 관련 케이스 제거

**수동 검증** — 두 기기를 오가는 시나리오는 자동화하지 않는다. 확장에서 단어 저장 →
앱에서 확인, 앱에서 삭제 → 확장에서 사라짐, 기내 모드 저장 후 복구 시 업로드,
로그아웃 시 미동기 경고, A→B 계정 전환 시 캐시 비우기를 직접 확인한다.

---

## 13. 구현 순서

이 스펙은 단일 기능이지만 덩어리가 크다. 각 단계가 끝난 시점에 앱과 확장이 모두
동작하는 상태를 유지하도록 아래 순서를 지킨다.

1. **Firebase 프로젝트 준비** — 프로젝트 생성, 이메일/비밀번호 공급자 활성화,
   §11.1 규칙 배포, `cloud/config.js`와 `firebase_options.dart` 생성.
   **규칙 배포가 다른 모든 단계보다 먼저다**
2. **스키마 확장** — §6.2 필드 추가, 앱 DB v3→4 마이그레이션, 확장 1회
   마이그레이션. 동기화 코드 없이 필드만 채워지는 상태로 끝난다
3. **인증** — `cloud/auth.js`, `auth/login.html`, 앱 `AuthService`·`AuthGate`·
   `LoginScreen`, §5 강제 지점. 이 시점엔 로그인해도 아무것도 동기화되지 않는다
4. **동기화** — `firestore-rest.js`, `sync.js`, `sync_service.dart`, §7 전체,
   §7.5 상태 표시
5. **제거와 정리** — §8의 `.sqlite` 경로 제거, 4탭화, JSON 내보내기, 목업 갱신.
   4단계가 검증된 뒤에 지운다 — 순서가 뒤집히면 기존 사용자의 데이터 이동 경로가
   잠시 끊긴다

---

## 14. 범위 밖 (재확인)

- Google / Apple 소셜 로그인
- 비밀번호 재설정 이메일, 이메일 주소 인증
- 자막 오버레이 설정과 진행 중 타이머 세션의 동기화
- 실시간 리스너
- Claude API 연동, 인앱결제, 복습 알고리즘 교체 (Phase C 이후 단계)
- Cloud Functions 백엔드 — AI 기능 착수 시 이 설계 위에 얹는다
