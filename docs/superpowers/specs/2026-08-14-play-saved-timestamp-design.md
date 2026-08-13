# 저장된 타임스탬프 재생 기능 설계

**날짜:** 2026-08-14
**상태:** 승인됨
**상위 문서:** `docs/superpowers/specs/2026-08-02-phase-b-flutter-app-design.md`

---

## 1. 배경

Chrome 확장 프로그램에서 단어/문장을 저장할 때 이미 `platform`/`contentId`/`timestamp`
필드가 함께 저장된다 (design.md §3.5). 지금까지 모바일 앱은 이 정보를 텍스트로만
보여줬을 뿐, 실제로 그 순간의 영상을 다시 볼 방법이 없었다. 이 기능은 YouTube에서
저장한 항목에 한해 앱 안에서 바로 그 타임스탬프로 재생할 수 있게 한다.

Netflix/Disney+/쿠팡플레이는 DRM 보호 콘텐츠라 공식 임베드 플레이어가 없고, 서드파티
앱이 그 안의 영상을 재생할 방법이 없다 — 이번 범위에서 제외한다.

## 2. 범위

- **지원 플랫폼:** YouTube만. `Word`/`Sentence.platform !== 'youtube'`인 항목은
  재생 버튼 자체를 숨긴다.
- **진입점:** Home 화면의 단어/문장 리스트 항목을 탭 → 신규 상세 화면으로 이동.
  상세 화면에 재생 버튼을 둔다 (리스트 항목 자체에 재생 아이콘을 붙이지 않는다).
- **재생 방식:** 상세 화면 안에서 유튜브 임베드 플레이어를 그 자리에 렌더링,
  저장된 `timestamp`(초)부터 바로 시작한다.
- **범위 밖:** Netflix/Disney+/쿠팡플레이 딥링크(작품 페이지만 여는 얕은 딥링크
  조차도), 재생 중 자막 오버레이, 재생 기록/이어보기.

## 3. 데이터 모델

기존 `Word`/`Sentence` 모델에 이미 `platform`(String), `contentId`(String),
`timestamp`(double, 초 단위) 필드가 있다 — **스키마 변경 없음**. 상세 화면은 이
필드들을 그대로 읽어 쓴다.

## 4. 아키텍처

새 의존성: `youtube_player_flutter` (공식 YouTube IFrame API 래퍼, `startSeconds`
파라미터로 지정 시점부터 재생 지원).

새 화면: `mobile/lib/features/home/item_detail_screen.dart`
- `ItemDetailScreen`이 `Word` 또는 `Sentence` 중 하나를 받는다 (두 모델이 서로
  다른 필드명을 쓰므로 — `word`/`original`, `definition`/`translation` 등 — 공통
  표시 로직을 위해 화면 진입 시점에 두 모델을 하나의 내부 뷰모델로 정규화한다.
  Task 8의 `FlashcardItem`이 이미 같은 문제를 같은 방식으로 풀었으므로 그 패턴을
  재사용한다).
- 표시 정보: 단어/원문, 뜻/번역, 출처(플랫폼·콘텐츠 제목·타임스탬프).
- `platform == 'youtube'`일 때만 재생 버튼 노출. 탭하면 같은 화면 안에서
  `YoutubePlayerController(initialVideoId: contentId, params: ...startAt: timestamp.toInt())`
  로 플레이어를 초기화하고 인라인으로 재생한다 (전체화면 전환이나 별도 라우트
  없이, 상세 화면 안에 플레이어가 나타나는 형태).

`HomeScreen`의 `_WordList`/`_SentenceList`가 만드는 `ListTile`에 `onTap`을 추가해
`ItemDetailScreen`으로 네비게이션한다.

## 5. 데이터 흐름

- 상세 화면 진입 시 별도 네트워크/DB 호출 없음 — Home 화면에서 이미 로드된
  `Word`/`Sentence` 객체를 라우트 인자로 그대로 전달한다.
- 재생 버튼 탭 → 플레이어 위젯 마운트 → YouTube IFrame API가 지정된 `contentId`의
  영상을 `timestamp`초부터 로드.

## 6. 에러 처리

- `contentId`가 비어있거나 11자리 YouTube 영상 ID 형식이 아니면 재생 버튼 대신
  "재생할 수 없는 항목입니다" 안내 텍스트를 표시한다.
- 네트워크 문제나 영상이 삭제/비공개 처리된 경우의 에러 UI는
  `youtube_player_flutter` 패키지의 기본 동작에 위임한다 (자체 재구현하지 않음).

## 7. 테스트

- `ItemDetailScreen`이 `Word`를 받았을 때와 `Sentence`를 받았을 때 각각 올바른
  필드가 표시되는지 위젯 테스트.
- `platform == 'youtube'`일 때 재생 버튼이 보이고, 그 외 플랫폼일 때 숨겨지는지
  위젯 테스트.
- 유효하지 않은 `contentId`일 때 안내 텍스트가 뜨는지 위젯 테스트.
- `youtube_player_flutter` 위젯 자체의 내부 동작(실제 재생, 시킹)은 서드파티
  패키지 영역이므로 테스트 범위에서 제외한다.

## 8. 범위 밖 (재확인)

- Netflix/Disney+/쿠팡플레이 딥링크 (작품 페이지만 여는 얕은 딥링크 포함)
- 재생 중 이중 자막 오버레이
- 재생 기록/이어보기 기능
