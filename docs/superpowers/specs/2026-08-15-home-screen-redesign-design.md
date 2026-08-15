# 홈 화면(1c) 재설계

**날짜:** 2026-08-15
**상태:** 승인됨
**상위 문서:** `docs/superpowers/specs/2026-07-17-english-helper-design.md`, Claude Design 목업 `English Helper UI.dc.html` §1c

---

## 1. 배경

`feature/design-tokens` 브랜치에서 공유 디자인 토큰(색상·서체)을 도입했지만, 화면 레이아웃 자체는 아직 기본 Material 구조 그대로다. 이 스펙은 목업 §1c("홈 — 저장 목록 (탭·필터 동작)")의 실제 레이아웃을 `mobile/lib/features/home/home_screen.dart`에 반영한다.

## 2. 범위

- **포함:** 홈 화면 헤더(제목+개수+검색), 단어/문장 세그먼트 토글, 플랫폼 필터 칩, 카드형 리스트 아이템, 검색 기능.
- **제외:** "마지막 가져오기" 날짜 표시(데이터 파이프라인에 저장 기능 없음 — 별도 스코프), 서버사이드 필터링/페이지네이션(현재 리포지토리 API가 전체 목록만 반환하므로 이번 스펙에서는 클라이언트 사이드 필터로 처리하고 리포지토리 인터페이스는 바꾸지 않음).

## 3. 데이터 흐름

`LearningRepository.getWords()`/`getSentences()`는 파라미터 없이 전체 목록을 반환한다 (변경 없음). `HomeScreen`은 `StatefulWidget`으로 전환하여:
1. `initState`에서 두 목록을 한 번 로드해 메모리에 보관.
2. 검색어(`TextEditingController`)와 선택된 플랫폼 필터(`String? selectedPlatform`, null=전체)를 로컬 state로 관리.
3. 화면에 그릴 리스트는 `words.where((w) => matchesFilter(w))`로 매 빌드마다 파생 — 별도 캐싱 없음(항목 수가 수백 단위이므로 충분히 가볍다).

플랫폼 필터 칩 목록은 로드된 데이터에서 등장하는 고유 `platform` 값을 동적으로 추출해 만든다("전체"는 항상 첫 칩으로 고정 추가).

## 4. 신규 공유 컴포넌트

### `mobile/lib/shared/widgets/platform_badge.dart`

```dart
class PlatformBadge extends StatelessWidget {
  final String platform;
  const PlatformBadge({super.key, required this.platform});

  static const _styles = {
    'youtube': (label: 'YouTube', bg: Color(0x1AFF0000), fg: Color(0xFFCC0000)),
    'netflix': (label: 'Netflix', bg: Color(0x1AE50914), fg: Color(0xFFB0060F)),
    'disney': (label: 'Disney+', bg: Color(0x1A0063E5), fg: Color(0xFF0050B8)),
    'coupang': (label: '쿠팡플레이', bg: Color(0x1A00C73C), fg: Color(0xFF00A030)),
  };

  @override
  Widget build(BuildContext context) {
    final style = _styles[platform.toLowerCase()] ??
        (label: platform, bg: const Color(0x14454D5E), fg: AppColors.inkTertiary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(color: style.bg, borderRadius: BorderRadius.circular(4)),
      child: Text(
        style.label,
        style: TextStyle(
          fontFamily: AppFonts.mono,
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.06,
          color: style.fg,
        ),
      ),
    );
  }
}
```

디자인 시스템 원칙("플랫폼 배지만 예외로 색을 갖고, 그 외에는 잉크 단계로 해결" — design.md §5.1/목업 §1a)에 따라, 색을 갖는 유일한 요소로 플랫폼 배지를 남긴다. 알 수 없는 플랫폼 값은 회색 폴백으로 처리한다.

### `mobile/lib/shared/format/timestamp_format.dart`

```dart
String formatTimestamp(double seconds) {
  final total = seconds.toInt();
  final m = total ~/ 60;
  final s = total % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}
```

`item_detail_screen.dart`의 기존 private `_formatTimestamp`와 동일 로직 — 이번 작업으로 공유 함수로 승격하고 `item_detail_screen.dart`도 이걸 쓰도록 교체한다(같은 화면 계열이 서로 다른 포맷터를 갖지 않도록). `timer_screen.dart`의 `HH:MM:SS` 포맷터는 용도가 달라(누적 학습 시간) 그대로 둔다.

## 5. 화면 구조

```
Scaffold
  body: CustomScrollView 또는 Column
    ┌ 헤더 영역 (padding 20px)
    │   "저장한 표현" (headlineLarge) + "{count}개" (bodySmall)
    │   검색 아이콘 버튼 (탭 시 검색 필드로 전환, 다시 탭하면 복귀)
    ├ 세그먼트 토글 (단어 {n} / 문장 {n})
    ├ 플랫폼 필터 칩 (가로 스크롤)
    └ 리스트 (필터링된 words 또는 sentences)
        각 아이템: 기존 Dismissible(스와이프 삭제 유지) 안에 새 카드 위젯
        탭 → 기존 ItemDetailScreen(item: DetailItem.fromWord/fromSentence) 이동 (변경 없음)
```

**단어 카드:** 단어(titleLarge) · 뜻(bodyMedium) · 정의(bodySmall) · 예문(왼쪽 보더 인용구 스타일) · 하단 행(PlatformBadge + contentTitle 말줄임 + 시간 배지)

**문장 카드:** 원문(bodyLarge) · 번역(bodyMedium) · 하단 행(단어 카드와 동일 구성)

빈 상태는 기존 `EmptyState` 위젯 재사용(검색/필터 결과가 0건일 때는 "검색 결과가 없어요" 메시지로 분기, 데이터 자체가 0건일 때는 기존 "아직 저장된 항목이 없어요..." 메시지 유지).

## 6. 에러 처리

- 검색/필터 결과 0건: `EmptyState(message: '검색 결과가 없어요')`.
- 데이터 로딩 중: 기존과 동일하게 `FutureBuilder`의 로딩 상태 처리(또는 `initState`의 `Future` 완료 전까지 `CircularProgressIndicator`).
- 알 수 없는 platform 값: `PlatformBadge`가 회색 폴백 + 원본 문자열 그대로 표시(위 §4 참고), 예외를 던지지 않음.

## 7. 테스트

- 플랫폼 필터 칩을 탭하면 해당 플랫폼 항목만 리스트에 남는지 위젯 테스트.
- 검색어를 입력하면 헤드라인/본문에 부분일치하는 항목만 남는지 위젯 테스트.
- 단어/문장 세그먼트 전환 시 각 탭의 개수 배지가 실제 항목 수와 일치하는지 위젯 테스트.
- `PlatformBadge`가 `youtube`/`netflix`/`disney`/`coupang`/미지정 값 각각에 대해 올바른 라벨을 렌더링하는지 위젯 테스트.
- 검색/필터 결과 0건일 때 "검색 결과가 없어요" 메시지가 뜨는지, 데이터 자체가 0건일 때 기존 안내 문구가 뜨는지 위젯 테스트.
- 기존 스와이프 삭제·탭-상세이동 동작이 새 카드 위젯에서도 유지되는지 위젯 테스트(회귀 확인).
- `formatTimestamp()`의 경계값(0초, 59초, 60초, 소수점 초) 단위 테스트.

## 8. 범위 밖 (재확인)

- "마지막 가져오기" 날짜 표시
- 서버사이드/DB 레벨 필터링, 페이지네이션
- IPA/발음기호 표시 (데이터 파이프라인에 저장되지 않음 — 목업엔 있으나 실제 데이터 없음)
