# 집중 타이머 기능 설계

**날짜:** 2026-08-09
**상태:** 승인됨
**상위 문서:** `docs/superpowers/specs/2026-08-02-phase-b-flutter-app-design.md`

---

## 1. 배경

Phase B Flutter 앱(Home/Flashcard/Import/Settings)이 이미 배포되어 있다. 이번 기능은
그 위에 얹는 독립적인 학습 시간 측정 기능이다 — 플래시카드 복습과는 무관하게, 사용자가
직접 시작/일시정지/종료하는 범용 집중 타이머로 하루 공부량을 재고, 주간/월간/년간으로
누적해서 그래프나 숫자로 볼 수 있으며, 주간 목표 대비 진행률을 표시한다.

## 2. 범위

- **타이머 대상:** 독립적인 수동 타이머. 플래시카드 화면과 연동하지 않는다.
- **네비게이션:** 바텀 네비게이션에 5번째 탭 "타이머" 추가 (기존 4탭: 홈/플래시카드/가져오기/설정).
- **타이머 컨트롤:** 시작 / 일시정지 / 재개 / 종료. 일시정지 구간은 공부 시간에서 제외한다.
- **백그라운드 동작:** 앱을 끄거나 백그라운드로 보내도 계속 측정한다 (별도 백그라운드
  서비스 없이, 시작 시각을 영속 저장해두고 재실행 시 경과 시간을 계산하는 방식).
- **주간 목표:** 사용자가 설정 가능. 목표를 바꾸면 **바꾼 시점 이후 주부터만** 새 목표가
  적용되고, 과거 주는 그 당시 설정된 목표로 고정된다.
- **범위 밖:** 알림/리마인더, 다른 사용자와의 비교, 플래시카드 세션과의 자동 연동, 일별
  목표(주간 목표만 지원).

## 3. 데이터 모델

**진행 중인 세션 상태** — `shared_preferences`에 저장 (완료되지 않은 세션은 히스토리가
아니므로 DB에 넣지 않는다):

```
key: 'timer_active_session'
value (JSON): {
  startedAt: ISO8601,
  pausedAt: ISO8601 | null,       // 현재 일시정지 중이면 그 시작 시각, 아니면 null
  accumulatedPausedSeconds: int,  // 지금까지 일시정지로 제외된 총 시간
}
```

경과 시간 계산:
- 실행 중: `now - startedAt - accumulatedPausedSeconds`
- 일시정지 중: `pausedAt - startedAt - accumulatedPausedSeconds`

**완료된 세션** (`study_sessions` 테이블, 새로운 앱 로컬 DB 테이블):

```sql
CREATE TABLE study_sessions (
  id TEXT PRIMARY KEY,
  started_at TEXT NOT NULL,
  ended_at TEXT NOT NULL,
  duration_seconds INTEGER NOT NULL,  -- 일시정지 시간 제외한 순수 집중 시간
  saved_at TEXT NOT NULL
);
```

**주간 목표 이력** (`weekly_goals` 테이블):

```sql
CREATE TABLE weekly_goals (
  id TEXT PRIMARY KEY,
  target_minutes INTEGER NOT NULL,
  effective_from TEXT NOT NULL,  -- 이 날짜가 속한 주(월요일 시작)부터 적용
  created_at TEXT NOT NULL
);
```

특정 주의 유효 목표 조회: `effective_from <= 그 주 월요일 날짜`인 행 중
`effective_from`이 가장 최신인 것 하나. 목표를 아직 한 번도 설정 안 했으면 이 테이블은
비어 있고, 화면엔 "목표를 설정해보세요" 안내가 뜬다.

## 4. 아키텍처

`LearningRepository`와는 별개로 `StudyTimerRepository`(추상 인터페이스 + sqflite 구현체)를
신설한다 — 기존 `words`/`sentences` 도메인과 섞지 않고 독립된 관심사로 분리한다. 같은
sqflite `Database` 인스턴스(같은 파일)를 공유하되, 테이블과 리포지토리 클래스는 분리한다.

```dart
abstract class StudyTimerRepository extends ChangeNotifier {
  Future<void> startSession();
  Future<void> pauseSession();
  Future<void> resumeSession();
  Future<void> endSession();          // study_sessions에 저장 + active state 삭제
  ActiveSessionState? getActiveSession(); // 동기, 메모리 캐시 (UI 매초 갱신용)

  Future<List<StudySession>> getSessionsBetween(DateTime start, DateTime end);
  Future<int?> getWeeklyGoalMinutes(DateTime forWeekStart);
  Future<void> setWeeklyGoal(int targetMinutes); // effective_from = 이번 주 월요일
}
```

집계(주/월/년 합산, 일자별 막대그래프용 데이터)는 `getSessionsBetween`으로 가져온 뒤
Dart 쪽에서 그룹핑한다 — 데이터 규모가 작아 SQL `GROUP BY`와 인메모리 집계 중 어느 쪽이든
상관없지만, 리포지토리 인터페이스를 단순하게 유지하기 위해 "범위로 가져와서 화면에서
접는" 방식을 택한다.

그래프는 **`fl_chart`** 패키지를 새 의존성으로 추가한다 (Flutter 생태계 표준, 가볍고
무료 — Syncfusion 등 상업 라이선스가 필요한 대안은 이 규모에 과하다).

## 5. 화면 구성

바텀 네비게이션 5탭: 홈 / 플래시카드 / 가져오기 / 설정 / **타이머**.

**타이머 탭**
- 상단: 큰 시간 표시(HH:MM:SS) + 시작/일시정지/재개/종료 버튼. 버튼은 상태에 따라
  토글 (정지 상태 → [시작]만, 실행 중 → [일시정지][종료], 일시정지 중 → [재개][종료])
- 그 아래: 주간/월간/년간 세그먼트 전환
- 그래프 뷰 ↔ 숫자(리스트) 뷰 토글 — 그래프는 `fl_chart` 막대그래프(선택한 기간 내
  일/주/월 단위 막대), 숫자 뷰는 같은 데이터를 텍스트 리스트로
- 이번 주 목표 대비 진행률 바 (목표 미설정 시 "목표를 설정해보세요" + 설정 버튼)

## 6. 데이터 흐름

- **시작**: `StudyTimerRepository.startSession()` → `shared_preferences`에 활성 세션
  상태 기록, 화면은 1초 타이머(`Timer.periodic`)로 표시만 갱신 (DB 쓰기는 없음)
- **일시정지**: `pausedAt` 기록
- **재개**: 방금 일시정지 구간을 `accumulatedPausedSeconds`에 더하고 `pausedAt = null`
- **종료**: `duration_seconds` 계산해서 `study_sessions`에 insert, `shared_preferences`의
  활성 세션 상태 삭제
- **앱 재시작 시 복원**: 앱 시작 시 `shared_preferences`에 활성 세션이 있으면 그 상태로
  타이머 화면을 복원 (일시정지 중이었으면 일시정지 상태로, 실행 중이었으면 경과 시간을
  현재 시각 기준으로 재계산해서 이어서 표시)

## 7. 에러 처리

- 목표 미설정 → 진행률 바 대신 안내 문구 + 설정 버튼
- 선택한 기간에 기록이 없음 → 그래프/리스트 모두 빈 상태 문구
- 앱이 예기치 않게 종료됐다가 재시작 → 활성 세션 상태로 정상 복원 (위 데이터 흐름 참고,
  별도 손실 처리 불필요)

## 8. 테스트

- `StudyTimerRepository`의 세션 시작/일시정지/재개/종료 및 경과 시간 계산 로직에 대한
  unit test (일시정지 구간이 정확히 제외되는지가 핵심 케이스)
- `weekly_goals` 조회 로직(특정 주에 대해 가장 최근의 유효한 목표를 고르는지) unit test
- 화면은 기존 Phase B 화면들과 동일하게 최소 스모크 테스트만 (빈 상태 렌더링, 시작→일시정지→종료
  버튼 상태 전환 확인 정도)

## 9. 범위 밖 (재확인)

- 알림/리마인더
- 다른 사용자와의 비교/랭킹
- 플래시카드 세션과의 자동 연동
- 일별 목표 (주간 목표만)
