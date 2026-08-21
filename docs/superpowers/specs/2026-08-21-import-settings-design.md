# 가져오기 · 설정 화면 (1f) 설계

**날짜:** 2026-08-21
**상태:** 승인됨
**상위 문서:** Claude Design 목업 `English Helper UI.dc.html` §1f

---

## 1. 배경

가져오기(`import_screen.dart`)와 설정(`settings_screen.dart`) 화면은 Phase B 때 만든 뒤로 한 번도
목업에 맞춰 재설계되지 않았다 (가져오기는 AppBar + 버튼 하나뿐, 설정은 모국어 드롭다운 + DB 경로
표시뿐). 목업 §1f는 두 화면을 하나의 단위로 묶어 보여주며, 훨씬 풍부한 내용을 담고 있다.

## 2. 범위

- **포함:** 가져오기 화면 전체 재설계(드롭존, 파일 선택 버튼, LAST IMPORT 카드), 설정 화면 전체
  재설계(학습/플래시카드/데이터 3개 섹션), `mergeFromFile`의 중복 건너뜀 개수 반환, "마지막
  가져오기" 결과의 SharedPreferences 영속화.
- **제외:** "하루 복습 목표"/"앞면에 표시"/"출처 문장 함께 보기" 설정값을 플래시카드 화면 로직에
  실제로 연결하는 작업 (저장만 하고 아직 소비하지 않음 — 기존 "모국어" 설정과 동일한 패턴).
  Chrome 확장 팝업(1g), 영상 오버레이(1h) 화면은 별도 작업.

## 3. 가져오기 화면 구조

### 3.1 레이아웃

AppBar 없이 Home/Timer 화면과 동일한 큰 타이틀 패턴을 따른다 (`SafeArea` + 상단 20px 패딩).

- 제목 "가져오기" (26px, 600 weight) + 설명문 ("확장 프로그램 팝업에서 내보낸 .sqlite 파일을
  선택하면 기존 데이터와 합칩니다. 같은 항목은 건너뜁니다.", 13px, `AppColors.inkTertiary`).
- 드롭존 카드: 점선 테두리(`#d4dae5`), 대각선 줄무늬 배경(모바일에는 실제 드래그앤드롭이 없으므로
  순수 장식), 높이 190, 라운드 16. 내부에 업로드 아이콘(44×44 원형 박스) + "english_helper.sqlite"
  캡션(mono, 11px). **탭하면 파일 선택기가 열린다** (버튼과 동일한 동작 — 시각적으로만 분리된 같은
  탭 타겟).
- "파일 선택" 버튼 (52px 높이, 전체 폭, accent 배경, 라운드 12).
- LAST IMPORT 카드 — **마지막으로 성공한 가져오기가 있을 때만 표시**, 없으면 완전히 숨김:
  - 헤더 "LAST IMPORT" (mono, 10.5px, letter-spacing 0.1em, `inkQuaternary`)
  - 날짜/시간(`8월 11일 오후 9:24` 형식) + 우측 "+{new}개" 배지(mono, `accentInk`)
  - 요약 줄: "단어 {newWords} · 문장 {newSentences} 추가, 중복 {skipped}건 건너뜀"
    (`skipped = skippedWords + skippedSentences`)

### 3.2 동작

- 파일 선택 성공 시: 기존과 동일하게 스낵바로 결과를 알리고, **동시에** 마지막 가져오기 결과를
  저장해 LAST IMPORT 카드를 즉시 갱신한다.
- 잘못된 백업 파일(`InvalidBackupFileException`): 기존과 동일하게 다이얼로그로 오류 메시지 표시.
  이 경우 LAST IMPORT 카드는 갱신하지 않는다 (실패한 시도는 기록하지 않음).

## 4. 데이터 계층 변경

### 4.1 `MergeResult` 확장

```dart
class MergeResult {
  final int newWords;
  final int newSentences;
  final int skippedWords;
  final int skippedSentences;
  const MergeResult({
    required this.newWords,
    required this.newSentences,
    required this.skippedWords,
    required this.skippedSentences,
  });
}
```

`mergeFromFile`의 기존 삽입 루프에서 `rowId == 0`(중복으로 무시됨)일 때 `skippedWords`/
`skippedSentences`를 증가시킨다 — 추가 쿼리 없이 기존 루프 안에서 계산 가능.

### 4.2 마지막 가져오기 영속화

`LearningRepository`에 새 메서드 추가:

```dart
abstract class LearningRepository extends ChangeNotifier {
  // ... 기존 메서드들 ...
  Future<LastImportSummary?> getLastImportSummary();
}

class LastImportSummary {
  final DateTime importedAt;
  final int newWords;
  final int newSentences;
  final int skippedWords;
  final int skippedSentences;
  const LastImportSummary({
    required this.importedAt,
    required this.newWords,
    required this.newSentences,
    required this.skippedWords,
    required this.skippedSentences,
  });
}
```

`LocalSQLiteRepository`는 `SharedPreferences`를 생성자에서 주입받도록 확장한다 (기본값은
`SharedPreferences.getInstance`, `StudyTimerRepository`의 `_getPrefs` 패턴과 동일). `mergeFromFile`
성공 시 결과를 JSON으로 인코딩해 `SharedPreferences`에 저장하고, `getLastImportSummary()`가 이를
읽어 디코딩한다. 실패(예외 발생) 시에는 저장하지 않는다.

## 5. 설정 화면 구조

AppBar 없이 동일한 큰 타이틀 패턴("설정"). 3개 섹션, 각각 mono 라벨 헤더(10.5px, letter-spacing
0.1em, `inkQuaternary`) + 흰 배경 라운드 카드(구분선 있는 행들).

### 5.1 학습

- **모국어**: 기존 `native_lang` 프리퍼런스 그대로 사용. 행을 탭하면 언어 목록을 보여주는
  `_ChoiceSheet` 바텀시트가 열린다 (기존 인라인 `DropdownButton`을 목업의 "탭하면 선택기가
  열리는" 행 스타일로 교체 — §5.2의 앞면에 표시 설정과 같은 위젯을 공유).
- **하루 복습 목표**: 신규. `SharedPreferences`에 정수로 저장(`daily_review_goal`, 기본값 20).
  행을 탭하면 −/+ 스테퍼가 있는 간단한 다이얼로그가 열린다 (목업에 이 설정 자체의 편집 UI가
  없으므로 자유롭게 설계 — 주간 목표 시트처럼 크게 만들 필요 없음). 플래시카드 화면에는 아직
  연결하지 않는다.
- **주간 학습 목표**: 신규 행이지만 로직은 이미 존재 — `StudyTimerRepository.getWeeklyGoalMinutes`/
  `setWeeklyGoal`를 그대로 읽어 "{H}시간"으로 표시하고, 탭하면 Timer 화면에서 이미 구현한
  `_GoalSheet`(주간 학습 목표 바텀시트)를 **그대로 재사용**해서 연다. 이를 위해 `_GoalSheet`를
  `weekly_goal_card.dart`에서 공개(`class GoalSheet` — private `_GoalSheet`에서 이름 변경)하고
  두 화면 모두에서 import한다.

### 5.2 플래시카드

- **앞면에 표시**: 신규. `SharedPreferences`에 문자열로 저장(`flashcard_front`, 값 `'en'|'ko'`,
  기본값 `'en'`). 탭하면 모국어 선택과 동일한 형태의 선택 목록 바텀시트가 열린다(영어/한글
  두 행, 현재 값에 체크마크) — §5.1의 모국어 선택기와 같은 재사용 가능한 위젯(`_ChoiceSheet`)으로
  구현해 목록 항목만 다르게 전달한다.
- **출처 문장 함께 보기**: 신규. `SharedPreferences`에 불리언으로 저장(`show_source_sentence`,
  기본값 true). 목업 그대로 `Switch` 위젯으로 즉시 토글.
- 두 설정 모두 플래시카드 화면 렌더링 로직에는 연결하지 않는다 (§2 범위 제외).

### 5.3 데이터

- **DB 파일 경로**: 기존 그대로 유지.
- **저장된 항목**: 신규. `(await repo.getWords()).length + (await repo.getSentences()).length`.
- 하단 캡션: "English Helper 0.4.0 · Phase B" (고정 텍스트, 정적).

## 6. 에러 처리

- LAST IMPORT 카드: `getLastImportSummary()`가 `null`을 반환하면(한 번도 가져온 적 없음) 카드
  자체를 렌더링하지 않는다.
- 하루 복습 목표 스테퍼: 최솟값 1개로 클램프(0 이하 방지).
- 설정 화면의 모든 `SharedPreferences` 읽기는 위젯 `initState`에서 비동기로 로드하고, 로드
  전에는 각 값의 안전한 기본값(위 기본값들)으로 렌더링한다 — 깜빡임 방지를 위해 별도의 로딩
  스피너를 두지 않는다.

## 7. 테스트

- `mergeFromFile`: 중복 항목이 있는 파일을 가져올 때 `skippedWords`/`skippedSentences`가 정확히
  계산되는지.
- `LastImportSummary` 저장/조회: `mergeFromFile` 성공 후 `getLastImportSummary()`가 방금 저장한
  값을 정확히 반환하는지, 앱을 재시작한 것처럼 새 리포지토리 인스턴스로도 값이 유지되는지
  (같은 `SharedPreferences` 인스턴스를 공유하는 테스트 환경에서 검증).
- 가져오기 화면: 가져온 적 없을 때 LAST IMPORT 카드가 없는지, 가져오기 성공 후 카드가 나타나고
  값이 정확한지, 드롭존과 버튼 둘 다 탭하면 파일 선택기 호출을 트리거하는지(모킹 가능한 범위
  내에서), 가져오기 실패 시 카드가 나타나지 않는지.
- 설정 화면: 각 새 설정(하루 복습 목표/앞면에 표시/출처 문장 함께 보기)이 값을 바꾸면
  `SharedPreferences`에 저장되고 화면에 반영되는지, 저장된 항목 수가 정확한지, 주간 학습 목표
  행을 탭하면 `GoalSheet`가 열리고 저장 시 `StudyTimerRepository`에 반영되는지.

## 8. 범위 밖 (재확인)

- 하루 복습 목표/앞면에 표시/출처 문장 함께 보기를 플래시카드 화면 동작에 실제로 연결하는 것
- Chrome 확장 공유(Share Extension/Intent)를 통한 가져오기 — 기존 Phase B 설계 그대로 `file_picker`만 사용
- 드롭존의 실제 드래그앤드롭 (모바일 플랫폼 특성상 순수 장식)
