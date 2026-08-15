# 플래시카드 화면(1d) 재설계

**날짜:** 2026-08-15
**상태:** 승인됨
**상위 문서:** `docs/superpowers/specs/2026-07-17-english-helper-design.md` §5.1, Claude Design 목업 `English Helper UI.dc.html` §1d (2026-08-15 갱신본 — 타이핑 채점 카드로 변경됨)

---

## 1. 배경

현재 `mobile/lib/features/flashcard/flashcard_screen.dart`는 저장된 단어/문장 전체를 무작위 셔플한 큐 하나로 돌리는 단순 앞/뒤 뒤집기 카드다. 복습 완료 여부는 `reviewCount` 증가 + `nextReviewAt`을 항상 "+1일 고정"으로만 기록해, 실제로는 간격 반복이 전혀 동작하지 않는다. 목업 §1d는 이를 두 가지 축으로 확장한다: (1) 카드가 사용자에게 정답을 직접 입력하게 하는 능동 회상(active recall) 방식으로 바뀌었고, (2) 카드/목록 두 탭 + 항목 추가·수정 모달이 추가됐다.

## 2. 범위

- **포함:** 데이터 모델에 실제 복습 레벨(`review_level`)과 마지막 복습일(`last_reviewed_at`) 추가, 레벨 기반 간격 스케줄로 `next_review_at` 계산, 오늘 복습 대상만 카드 큐에 포함, 카드 모드를 타이핑 채점 방식으로 재설계, 목록 모드 신규 구현, 추가/수정 모달 신규 구현(생성·수정·삭제).
- **제외:** FSRS(옵션 A) 알고리즘 자체 구현 — 이번에는 §5.1에 리서치된 옵션 B(고정 확장형 스케줄)를 쓴다. `review_level`은 단순 int 컬럼이라 나중에 FSRS로 교체해도 마이그레이션·UI 재사용 가능. 오답 시 레벨 강등/재조정 로직도 이번 범위 밖 — "몰라요"는 기존과 동일하게 DB를 건드리지 않는다.

## 3. 데이터 모델

### 3.1 스키마 변경 (v2 → v3)

`mobile/lib/data/database.dart`에 `study_timer`가 v1→v2에서 썼던 것과 동일한 `onUpgrade` 패턴으로 `words`/`sentences` 테이블에 컬럼 2개를 추가한다:

```sql
ALTER TABLE words ADD COLUMN review_level INTEGER NOT NULL DEFAULT 0;
ALTER TABLE words ADD COLUMN last_reviewed_at TEXT;
ALTER TABLE sentences ADD COLUMN review_level INTEGER NOT NULL DEFAULT 0;
ALTER TABLE sentences ADD COLUMN last_reviewed_at TEXT;
```

기존 `next_review_at` 컬럼은 그대로 두되 의미를 재정의한다: 더 이상 "+1일 고정"이 아니라 `last_reviewed_at + 레벨별 간격`으로 계산되어 저장되는 파생값이다(레벨/최종복습일이 바뀔 때마다 재계산). `review_count`는 그대로 두고 "총 복습 시도 횟수" 카운터로만 계속 쓴다(레벨과 별개, 하위 호환).

`onCreate`의 CREATE TABLE 문에도 두 컬럼을 추가한다.

**`kWordsColumns`/`kSentencesColumns`는 건드리지 않는다.** 이 두 상수는 앱 자체 스키마가 아니라 Chrome 확장이 내보낸 백업 `.sqlite` 파일의 컬럼을 정확히 일치 검증(`hasValidSchema`, `mergeFromFile`에서 호출)하는 데 쓰인다 — 확장은 `review_level`/`last_reviewed_at`을 절대 내보내지 않으므로, 여기에 새 컬럼을 추가하면 실제 백업 파일이 전부 "올바른 백업 파일이 아닙니다"로 거부되는 회귀가 생긴다. `mergeFromFile`이 가져온 행을 `words`/`sentences`에 삽입할 때 `review_level`/`last_reviewed_at` 키가 없는 채로 삽입되며, 컬럼의 `DEFAULT 0`/`NULL`이 자동으로 채워지므로 동작에는 문제가 없다.

### 3.2 레벨 스케줄

| 레벨 | 이름 | 다음 복습까지 |
|---|---|---|
| 0 | 새 항목 | (예정일 없음 — 항상 오늘 큐에 포함) |
| 1 | 학습 중 | 1일 |
| 2 | 복습 필요 | 7일 |
| 3 | 익숙해짐 | 30일 |
| 4 | 완전히 외움 | 90일 |

레벨 이름은 목업 §1a 타이포 스케일에 맞춰 IBM Plex Mono 뱃지로 표시한다. `mobile/lib/data/models/word.dart`(및 `sentence.dart`)에 `reviewLevel`(`int`, 기본 0)과 `lastReviewedAt`(`String?`) 필드를 추가하고 `toMap`/`fromMap`/`copyWith`에 반영한다.

### 3.3 복습 완료/재큐잉 로직

`markWordReviewed`/`markSentenceReviewed`(플래시카드 "알아요" 버튼이 호출)를 변경한다:

- `reviewLevel = min(현재 reviewLevel + 1, 4)`
- `lastReviewedAt = DateTime.now().toIso8601String()`
- `nextReviewAt = lastReviewedAt + 레벨별 간격`(레벨 4는 90일 고정, 더 늘어나지 않음)
- `reviewCount`도 기존처럼 계속 +1(감사/통계용, 화면에 노출 안 함)

"다시"(카드 모드) / 목록 모드에서의 열람은 DB를 건드리지 않는다 — 로컬 재큐잉만.

수정 모달에서 레벨을 수동으로 고를 때는 새 리포지토리 메서드 `setWordReviewLevel(String id, int level)` / `setSentenceReviewLevel(String id, int level)`를 추가한다. 동작은 `markXReviewed`와 같은 계산(레벨 지정 + `lastReviewedAt=now` + `nextReviewAt` 재계산)이지만 레벨을 임의 값(0~4)으로 직접 지정할 수 있다는 점만 다르다.

## 4. 큐 필터링 (핵심 동작 변경)

`FlashcardScreen._loadQueue()`는 현재 전체 단어/문장을 무조건 섞어 큐에 넣는다. 이를 "오늘 복습 대상만" 포함하도록 바꾼다:

```dart
bool _isDue(int reviewLevel, String? nextReviewAt) {
  if (reviewLevel == 0) return true; // 새 항목은 항상 포함
  if (nextReviewAt == null) return true; // 안전망: 레벨은 있는데 예정일이 없으면 포함
  return DateTime.parse(nextReviewAt).isBefore(DateTime.now());
}
```

`getWords()`/`getSentences()`는 변경하지 않는다(스펙 전역 제약과 동일 — 리포지토리는 항상 전체 목록 반환, 필터는 클라이언트 사이드). 필터링된 결과만 셔플해 큐에 넣는다. 예: 레벨 3(30일 간격) 항목은 마지막 복습 후 30일이 지나기 전까지 플래시카드 큐에 다시 나타나지 않는다.

## 5. 화면 구조

### 5.1 상단 공통 (카드/목록 모드 모두)

`{{ dTitle }}`("플래시카드") + `{{ dMeta }}`(예: "복습 12개") 헤더, 카드/목록 세그먼트 토글(목록 탭에 전체 항목 수 배지), 타입 필터 칩(전체/단어/문장 3개 — 목업 `typeFilters`).

### 5.2 카드 모드 (타이핑 채점)

- **상단바**: 레벨 배지 + 간격(`fcLvName`/`fcLvGap`), 우측에 "마지막 복습 {날짜 또는 '없음'}"
- **진행 바**: 오늘 큐 소진율(`1 - 남은개수/최초개수`)
- **카드 앞면**: 프롬프트 라벨 + 프롬프트 텍스트. 단어는 "한글 뜻 → 영어 단어" 방향(프롬프트=번역/정의, 정답=`word.word`), 문장은 "번역 → 원문" 방향(프롬프트=번역, 정답=`sentence.original`).
- **답 입력**: 텍스트 필드 + 전송 버튼(→ 아이콘). 제출 시 trim + 대소문자 무시 비교로 채점, 정답/오답을 인라인 표시(오답이면 정답 문자열도 함께 보여줌).
- **카드 뒷면**(카드 탭하면 뒤집힘): 전체 상세(단어/한글뜻/정의/구분선/예문). **사용자가 입력한 답은 뒷면에 표시하지 않는다** — 정답 상세 정보만 보여준다.
- **하단 버튼**: "다시"(왼쪽, 항상 노출, DB 변경 없이 로컬 재큐잉) / "알아요"(오른쪽, **뒷면일 때만 노출**, `markWordReviewed`/`markSentenceReviewed` 호출 — 채점 결과와 무관하게 사용자가 최종 판단).

### 5.3 목록 모드 (신규)

레벨 필터 칩(전체 + 레벨 1~4, 목업 `lvFilters`) 행, 항목 리스트(각 항목: 원문/번역, 레벨 배지, 예문 인용구, 하단 "마지막 복습 {날짜}" + 마감일 `it.due`), 탭하면 수정 모달. 우하단 "＋추가" FAB.

### 5.4 추가/수정 모달 (신규)

하단 시트: 취소/제목/저장 헤더, 단어/문장 토글, 영어 입력, 한글 뜻 입력, 응용 예문 textarea, 복습 상태 5단계 선택 리스트(라디오 형태, 탭하면 즉시 그 레벨로 `setWordReviewLevel`/`setSentenceReviewLevel` 호출 — 저장 버튼과 별개로 즉시 반영), 삭제 버튼(수정 모드에서만 노출, 기존 `deleteWord`/`deleteSentence` 재사용).

새 항목 생성 시 id는 `mobile/lib/data/study_timer_repository.dart`의 `_generateId()`와 같은 방식(랜덤 16자리 hex, 신규 패키지 의존성 없음)으로 만든다. 저장은 기존 `saveWord`/`saveSentence`(내부적으로 `INSERT OR REPLACE`라 신규/수정 모두 동일 호출로 처리 가능)를 그대로 쓴다.

## 6. 에러 처리

- 저장된 항목이 하나도 없으면(카드 모드): 기존 "아직 저장된 항목이 없어요..." 안내 유지.
- 오늘 복습 대상이 없으면(전체는 있지만 전부 예정일 전): "오늘 복습 완료! 🎉" 안내 유지(기존 문구 그대로 재사용, 의미는 "다 끝냈다"에서 "오늘 볼 게 없다"로 자연히 확장됨).
- 목록 모드에서 레벨 필터 결과가 0건: "해당 레벨의 항목이 없어요" 안내.
- 답 입력 필드가 비어있을 때 전송 버튼을 눌러도 채점하지 않음(빈 문자열 오답 처리 방지).

## 7. 테스트

- DB 마이그레이션: v2 스키마에서 v3로 열었을 때 `review_level`/`last_reviewed_at` 컬럼이 생기는지, 정확한 기본값(0/NULL)인지 (`database_test.dart` 기존 마이그레이션 테스트와 동일한 방식).
- `hasValidSchema`/`kWordsColumns`/`kSentencesColumns`가 이번 변경으로 전혀 달라지지 않았는지(회귀 방지) — 기존 백업파일 검증 테스트가 그대로 통과하는지 확인.
- `mergeFromFile`로 (review_level/last_reviewed_at이 없는) 구버전 백업 파일을 가져왔을 때 정상적으로 병합되고, 가져온 행의 `review_level`이 기본값 0으로 채워지는지.
- `markWordReviewed`/`markSentenceReviewed`: 레벨이 1씩 오르는지(최대 4에서 멈추는지), `lastReviewedAt`/`nextReviewAt`이 레벨별 간격대로 계산되는지.
- `setWordReviewLevel`/`setSentenceReviewLevel`: 임의 레벨로 직접 지정 가능한지.
- 큐 필터링(`_isDue`): 레벨 0은 항상 포함, 레벨 1~4는 `nextReviewAt` 이전이면 제외·이후면 포함되는 경계값 테스트.
- 카드 모드 채점: 정답 대소문자/공백 무시 비교, 오답 시 정답 노출, 빈 입력 제출 무시.
- 뒷면에 사용자가 입력한 답이 표시되지 않는지(회귀 방지 테스트로 명시).
- 목록 모드: 레벨 필터 칩 선택 시 목록이 좁혀지는지, 탭하면 수정 모달이 뜨는지.
- 추가/수정 모달: 신규 생성 시 새 id로 저장되는지, 수정 시 같은 id로 upsert되는지, 삭제 버튼이 수정 모드에서만 보이는지, 레벨 탭이 즉시 반영되는지.

## 8. 범위 밖 (재확인)

- FSRS(옵션 A) 알고리즘 구현
- 오답 시 레벨 자동 강등
- 카드 뒷면에 사용자가 입력한 답 표시 (요청에 따라 제외)
