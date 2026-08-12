# English Helper — 전체 서비스 설계

**날짜:** 2026-07-17  
**상태:** 승인됨  
**Phase:** A (Chrome Extension) → B (Flutter 앱) → C (Cloud + AI)

---

## 1. 서비스 개요

스트리밍 플랫폼(YouTube, Netflix, Disney+, 쿠팡플레이)에서 영어 자막을 활용해 학습하고, 저장한 단어/문장을 Flutter 모바일 앱에서 Flashcard로 복습하는 영어 학습 서비스.

**핵심 차별점:**
- 어댑터 패턴으로 신규 플랫폼을 파일 하나만 추가해 확장
- 플랫폼 공식 자막 두 트랙을 이중 자막으로 동시 표시 (번역 API 비용 없음)
- 출처 메타데이터(플랫폼, 콘텐츠, 시간) 포함 저장으로 컨텍스트 복습 가능
- Repository 추상화로 로컬 SQLite → Cloud 무중단 전환 가능

---

## 2. Phase 로드맵

| Phase | 범위 | 데이터 저장 |
|-------|------|------------|
| A | Chrome Extension 완성 | chrome.storage.local + SQLite export |
| B | Flutter 모바일 앱 + Flashcard | 로컬 SQLite 파일 직접 주입 |
| C | Cloud 백엔드 + AI Service + 인앱결제 | Cloud DB (Firebase / Supabase 등) |

---

## 3. Phase A — Chrome Extension

### 3.1 지원 플랫폼

| 플랫폼 | 어댑터 파일 | 자막 방식 |
|--------|------------|---------|
| YouTube | `adapters/youtube.js` | `track` 요소 + YT Player API |
| Netflix | `adapters/netflix.js` | `.player-timedtext` DOM 감지 |
| Disney+ | `adapters/disney.js` | `[data-testid="subtitle"]` DOM 감지 |
| 쿠팡플레이 | `adapters/coupang.js` | DOM 감지 (구조 분석 필요) |

### 3.2 파일 구조

```
english-helper-extension/
├── manifest.json                  # MV3, host_permissions 4개 플랫폼
├── background/
│   └── service_worker.js          # 메시지 라우팅, storage 관리, DB export
├── core/
│   ├── adapter-interface.js       # SubtitleAdapter 인터페이스 정의
│   ├── subtitle-engine.js         # 이중자막 렌더링, 시간 동기화
│   ├── script-panel.js            # 사이드패널 UI, 하이라이트 추적
│   ├── word-popup.js              # 단어 클릭 팝업 + Free Dictionary API
│   └── storage.js                 # StorageAdapter (chrome.storage → SQLite export)
├── adapters/
│   ├── youtube.js
│   ├── netflix.js
│   ├── disney.js
│   └── coupang.js
├── ui/
│   ├── side-panel.html
│   ├── side-panel.css
│   └── overlay.css
└── popup/
    ├── popup.html                  # 저장 목록, Export 버튼, 설정
    └── popup.js
```

### 3.3 SubtitleAdapter 인터페이스

모든 플랫폼 어댑터가 구현해야 할 계약. 신규 플랫폼 추가 = 이 인터페이스를 구현하는 파일 하나만 `adapters/`에 추가.

```js
class SubtitleAdapter {
  // 사용 가능한 자막 트랙 반환 (영어 + 모국어 트랙 포함)
  getSubtitleTracks()
  // → [{ lang: 'en', cues: [{ start: 142.5, end: 145.0, text: '...' }] }]

  getCurrentTime()          // → seconds (현재 재생 위치)
  seekTo(seconds)           // 해당 시간으로 이동
  onSubtitleChange(cb)      // 자막 변경 시 콜백 등록
  onTimeUpdate(cb)          // 재생 시간 변경 시 콜백 등록
  getPlatformMeta()         // → { platform, title, contentId }
  destroy()                 // 이벤트 리스너 정리
}
```

### 3.4 StorageAdapter

Phase C 전환 시 내부 구현만 교체, 호출부 코드 변경 없음.

```js
class StorageAdapter {
  async saveWord(wordData)       // chrome.storage.local에 저장
  async saveSentence(sentData)   // chrome.storage.local에 저장
  async getAll()                 // 전체 데이터 조회
  async exportToSQLite()         // .sqlite 파일 생성 + 다운로드 트리거
}
// Phase C: CloudStorageAdapter implements same interface → Cloud API 호출
```

### 3.5 데이터 모델

**Word**
```js
{
  id: uuid,
  word: "ephemeral",
  definition: "lasting for a very short time",
  sentence: "Nothing in life is ephemeral.",
  translation: "인생에서 덧없지 않은 것은 없다.",
  platform: "netflix",
  contentTitle: "Stranger Things S1E1",
  contentId: "platform-specific-id",
  timestamp: 142.5,
  savedAt: "ISO8601",
  reviewCount: 0,
  nextReviewAt: null          // Phase C AI 연동 시 활성화
}
```

**Sentence**
```js
{
  id: uuid,
  original: "Nothing in life is ephemeral.",
  translation: "인생에서 덧없지 않은 것은 없다.",
  platform: "netflix",
  contentTitle: "Stranger Things S1E1",
  contentId: "platform-specific-id",
  timestamp: 142.5,
  savedAt: "ISO8601",
  reviewCount: 0,
  nextReviewAt: null
}
```

### 3.6 SQLite 스키마

```sql
CREATE TABLE words (
  id TEXT PRIMARY KEY,
  word TEXT NOT NULL,
  definition TEXT,
  sentence TEXT,
  translation TEXT,
  platform TEXT,
  content_title TEXT,
  content_id TEXT,
  timestamp REAL,
  saved_at TEXT,
  review_count INTEGER DEFAULT 0,
  next_review_at TEXT
);

CREATE TABLE sentences (
  id TEXT PRIMARY KEY,
  original TEXT NOT NULL,
  translation TEXT,
  platform TEXT,
  content_title TEXT,
  content_id TEXT,
  timestamp REAL,
  saved_at TEXT,
  review_count INTEGER DEFAULT 0,
  next_review_at TEXT
);
```

### 3.7 UX 흐름

**이중 자막 오버레이**
- 플랫폼 기본 자막 DOM `visibility: hidden` 처리
- Extension이 동일 위치에 두 줄 렌더링
  - 영어: 흰색, 크게, 각 단어를 `<span>`으로 분리 (클릭 가능)
  - 모국어: 노란색, 작게 (플랫폼 제공 자막 트랙 사용)

**사이드 패널**
- 영상 오른쪽 슬라이드인, 전체 스크립트 타임라인
- 현재 재생 구간 자동 스크롤 + 하이라이트
- 스크립트 줄 클릭 → seek
- 각 줄 우측 **＋** 버튼 → 문장 저장
- 토글 버튼: 영상 우측 상단 플로팅

**단어 클릭 팝업**
- 영어 자막 단어 클릭 → 팝업 표시
- Free Dictionary API로 발음기호 + 뜻 표시
- [단어 저장] / [문장 저장] 버튼
- 저장 시 현재 문장 + 모국어 번역 + 출처 메타데이터 함께 저장

**Extension 팝업 (아이콘 클릭)**
- 저장된 단어/문장 목록
- SQLite Export 버튼
- 모국어 설정 (한국어/일본어/스페인어 등)
- Extension 켜기/끄기 토글

---

## 4. Phase B — Flutter 모바일 앱

### 4.1 테스트 단계 데이터 흐름

```
[Chrome Extension]
  popup에서 Export 클릭
  → english_helper.sqlite 다운로드
      ↓ (수동 복사)
[Flutter 앱]
  Import 화면에서 파일 선택
  → /Documents/english_helper.sqlite 읽기
```

### 4.2 프로젝트 구조

```
lib/
├── main.dart
├── data/
│   ├── database.dart              # sqflite 패키지로 SQLite 파일 읽기
│   ├── models/
│   │   ├── word.dart
│   │   └── sentence.dart
│   └── repository.dart            # LearningRepository 추상 클래스
├── features/
│   ├── home/                      # 저장된 단어/문장 목록 (탭)
│   ├── flashcard/                 # Flashcard 복습 UI
│   ├── import/                    # SQLite 파일 import (file_picker)
│   └── settings/                  # 모국어, DB 경로 설정
└── shared/
    └── widgets/
```

### 4.3 Repository 추상화

```dart
abstract class LearningRepository {
  Future<List<Word>> getWords();
  Future<List<Sentence>> getSentences();
  Future<void> saveWord(Word word);
  Future<void> saveSentence(Sentence sentence);
}

// Phase B
class LocalSQLiteRepository implements LearningRepository { ... }

// Phase C (교체만 하면 됨)
class CloudRepository implements LearningRepository { ... }
```

### 4.4 화면 구성

**Home (저장 목록)**
- 단어 / 문장 탭 전환
- 각 항목: 내용 + 번역 + 출처(플랫폼·콘텐츠·시간)

**Flashcard (복습)**
- 앞면: 단어 또는 문장
- 뒤집기 → 뒷면: 뜻/번역 + 출처 문장
- [몰라요] → 큐 뒤로 재삽입 / [알아요] → 오늘 복습 완료
- `nextReviewAt` 필드 유지 (Phase C AI 알고리즘 연동 준비)

**Import**
- `file_picker`로 `.sqlite` 파일 선택
- 기존 DB와 merge (중복 id 무시)
- 마지막 import 시각 표시

**Settings**
- 모국어 선택
- DB 파일 경로 표시
- Phase C Cloud 계정 연결 항목 추가 예정

---

## 5. Phase C — Cloud + AI (추후 설계)

| 항목 | 내용 |
|------|------|
| 데이터 저장 | Firebase Firestore 또는 Supabase |
| 인증 | Google / Apple 로그인 |
| AI Service | Claude API — 학습 패턴 분석, 맞춤 복습 추천, 문장 해설 |
| 복습 알고리즘 | SM-2 또는 AI 기반 맞춤 스케줄 |
| 인앱결제 | AI 기능 구독형 (iOS: StoreKit2, Android: Play Billing) |
| 전환 방법 | `StorageAdapter` / `LearningRepository` 구현체만 교체 |

### 5.1 복습 알고리즘 리서치 노트 (2026-08-12)

구현 시점에 참고할 두 가지 후보:

**A. Anki FSRS (Free Spaced Repetition Scheduler)** — Anki 23.10부터 기본값, SM-2를 대체.
- Difficulty(난이도) / Stability(안정성) / Retrievability(인출 확률) 3요소를 카드마다 추적하는
  머신러닝 모델. "다시/어려움/보통/쉬움" 응답 기록을 학습해 사용자별 망각 패턴에 맞춰
  가중치를 최적화함
- 개발자 Jarrett Ye가 2만 사용자·7억 리뷰 데이터로 학습, 같은 기억 유지율 기준 SM-2 대비
  복습 횟수 20~30% 절감
- 참고: [The Algorithm (fsrs4anki wiki)](https://github.com/open-spaced-repetition/fsrs4anki/wiki/The-Algorithm), [Anki FAQ](https://faqs.ankiweb.net/what-spaced-repetition-algorithm)

**B. 고정 확장형 스케줄 (더 단순한 대안)** — 에빙하우스 망각곡선 기반, Cepeda 외 2006년
메타분석(254개 연구·14,000명 이상)에서 분산 학습이 몰아서 학습보다 장기 기억에 일관되게
유리함을 확인:

| 복습 회차 | 간격 | 누적 시점 |
|---|---|---|
| 1차 | 1일 후 | Day 1 |
| 2차 | 2~3일 후 | Day 3~4 |
| 3차 | 1주 후 | Day 7 |
| 4차 | 2주 후 | Day 14~15 |
| 5차 | 1개월 후 | Day 30 |
| 6차 | 2개월 후 | Day 60 |

SM-2 기본값(초기 1일→6일, 이후 ease factor 2.5배씩 확장)도 이 원리의 변형.

**결정은 보류** — Phase C 착수 시 A(정교하지만 구현 복잡)와 B(단순하지만 개인화 없음) 중
선택. `Word`/`Sentence`의 `reviewCount`/`nextReviewAt` 필드는 이미 양쪽 방식 모두와
호환되도록 설계되어 있어 스키마 변경 없이 나중에 결정 가능.

---

## 6. 설계 결정 기록

| 결정 | 이유 |
|------|------|
| 어댑터 패턴 | 신규 플랫폼 추가 시 기존 코드 영향 없음 |
| 플랫폼 자막 트랙 활용 (번역 API 미사용) | 비용 0, 공식 번역 품질 |
| Free Dictionary API | 무료, 설치 불필요, 발음기호 포함 |
| 테스트 단계 SQLite 파일 직접 주입 | 클라우드 인프라 없이 즉시 E2E 테스트 가능 |
| Repository / StorageAdapter 추상화 | Phase C 전환 시 호출부 코드 변경 없음 |
| Flashcard 알고리즘 Phase C로 이연 | 데이터 축적 후 AI 기반으로 직접 구현이 더 효과적 |
