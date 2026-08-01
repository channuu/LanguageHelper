# Phase B — Flutter 모바일 앱 설계

**날짜:** 2026-08-02
**상태:** 승인됨
**상위 문서:** `docs/superpowers/specs/2026-07-17-english-helper-design.md` §4

---

## 1. 배경

Phase A(Chrome Extension)는 YouTube/Netflix 어댑터가 기능적으로 완성되어 있고(Disney+/쿠팡플레이는
별도 진행 중), 단어/문장을 `chrome.storage.local`에 저장한 뒤 `.sqlite` 파일로 export하는 기능까지
동작한다. Phase B는 이 SQLite 파일을 가져와 모바일에서 Flashcard로 복습하는 앱이다.

현재 저장소에는 Flutter 프로젝트가 전혀 없다 (`pubspec.yaml`, `lib/` 없음). 루트의
`flutter_integration.dart`는 Firebase 기반 구식 프로토타입 코드로, 이번 설계의 스키마·저장
방식과 맞지 않아 참고하지 않는다.

## 2. 범위

- **대상 플랫폼:** Android + iOS
- **MVP 범위:** 상위 스펙 §4.4의 4개 화면(Home / Flashcard / Import / Settings) 전부
- **상태관리:** Provider (앱 규모가 작고 서버 통신이 없어 가벼운 선택지로 충분)
- **Import 방식:** `file_picker`로 파일을 직접 선택 (Share Extension/Intent Filter 등 OS 네이티브
  공유 연동은 이번 범위에 넣지 않는다)
- **복습 알고리즘:** 상위 스펙 §6 결정대로 SM-2 등 스케줄링 로직은 Phase C로 이연. Phase B는
  세션 단위 큐 재삽입만 구현하고, `reviewCount`/`nextReviewAt` 필드는 값만 채워 스키마 호환을
  유지한다 (Phase C가 그대로 읽어 쓸 수 있도록).

## 3. 아키텍처

상위 스펙 §4.2 구조를 그대로 따른다. 이 규모(화면 4개, 서버 통신 없음, 로컬 DB 읽기 위주)에
레이어를 더 나누는 clean architecture(usecase/domain 계층 등)는 과설계라 배제한다.

```
lib/
├── main.dart                      # MaterialApp, Provider 루트, 바텀 네비게이션
├── data/
│   ├── database.dart              # sqflite 오픈/쿼리 (words, sentences 테이블)
│   ├── models/
│   │   ├── word.dart
│   │   └── sentence.dart
│   └── repository.dart            # LearningRepository(추상) + LocalSQLiteRepository(구현)
├── features/
│   ├── home/                      # 단어/문장 탭, 목록 + 스와이프 삭제
│   ├── flashcard/                 # 복습 큐, 카드 뒤집기, 몰라요/알아요
│   ├── import/                    # file_picker → merge import
│   └── settings/                  # 모국어 설정, DB 경로 표시
└── shared/
    └── widgets/                   # 공통 카드/버튼 등
```

`LearningRepository`를 `ChangeNotifierProvider`로 앱 루트에 등록해 4개 화면이 공유한다.
Phase C 전환 시 `CloudRepository`가 같은 인터페이스를 구현하도록 교체하면 되고, 호출부(화면
위젯)는 변경할 필요가 없다 (상위 스펙 §4.3 그대로).

```dart
abstract class LearningRepository extends ChangeNotifier {
  Future<List<Word>> getWords();
  Future<List<Sentence>> getSentences();
  Future<void> saveWord(Word word);
  Future<void> saveSentence(Sentence sentence);
  Future<void> deleteWord(String id);
  Future<void> deleteSentence(String id);
  Future<int> mergeFromFile(String filePath);   // import 시 사용, 반영된 신규 항목 수 반환
}
```

## 4. 데이터 모델 & 스키마

Chrome Extension이 export하는 스키마(상위 스펙 §3.5/§3.6)를 그대로 사용한다 — 변환 없이 앱
로컬 DB(`/Documents/english_helper.sqlite`)에 동일한 `words`/`sentences` 테이블 구조로 저장한다.
새 컬럼을 추가하지 않는다.

```dart
class Word {
  final String id, word, definition, sentence, translation;
  final String platform, contentTitle, contentId;
  final double timestamp;
  final String savedAt;
  final int reviewCount;
  final String? nextReviewAt;
}

class Sentence {
  final String id, original, translation;
  final String platform, contentTitle, contentId;
  final double timestamp;
  final String savedAt;
  final int reviewCount;
  final String? nextReviewAt;
}
```

## 5. 데이터 흐름

**Import**
1. `file_picker`로 `.sqlite` 파일 선택
2. 임시 경로에서 해당 파일을 sqflite로 열어 `words`/`sentences` 테이블 존재 여부와 컬럼을
   검사한다 — 스키마가 안 맞으면 파일을 열지 않고 3번 에러 처리로 간다
3. 앱 로컬 DB에 `id` 기준 upsert. 이미 존재하는 `id`는 건너뛴다 (상위 스펙 §4.4 "중복 id 무시"
   그대로 — 로컬 DB의 `reviewCount`/`nextReviewAt` 진행 상황을 덮어쓰지 않기 위함)
4. 반영된 신규 항목 수를 스낵바로 표시 ("단어 12개, 문장 5개를 가져왔습니다")

**Home**
- 로컬 DB 전체 조회, 단어/문장 탭 전환
- 각 항목: 내용 + 번역 + 출처(플랫폼·콘텐츠·시간) — 상위 스펙 §4.4 그대로
- 항목 스와이프 → 삭제 (상위 스펙엔 명시되어 있지 않지만, Extension 팝업에 이미 있는 기능이라
  앱에도 있어야 자연스럽다 — 데이터가 한쪽에서만 계속 쌓이고 지울 방법이 없으면 사용성이 떨어짐)

**Flashcard**
- 화면 진입 시 전체 단어+문장을 메모리 큐로 로드 (Word/Sentence 통합 큐, 셔플)
- 카드 탭 → 뒤집기(뜻/번역 + 출처 문장 노출)
- [몰라요] → 큐 맨 뒤로 재삽입, DB 변경 없음
- [알아요] → `reviewCount + 1`, `nextReviewAt`에 현재 시각+1일 저장(값만 채움, 아직 아무 로직도
  이 값을 읽지 않음) 후 큐에서 제거
- 큐가 비면 "오늘 복습 완료" 화면

**Settings**
- 모국어 선택 (Extension과 동일한 옵션 목록: 한국어/일본어/스페인어 등)
- DB 파일 경로 텍스트 표시만 (편집 불가)

## 6. 에러 처리

- Import한 파일이 `words`/`sentences` 테이블이 없거나 컬럼이 다름 → 다이얼로그로 "올바른
  English Helper 백업 파일이 아닙니다" 안내, 로컬 DB는 변경하지 않음
- 로컬 DB가 비어있음(최초 실행) → Home/Flashcard 모두 빈 상태 위젯("아직 저장된 항목이
  없어요. Import 탭에서 불러오세요")

## 7. 테스트

- `data/repository.dart`의 merge 로직(중복 id 무시, 반영 개수 카운트)에 대한 unit test
- `database.dart`의 스키마 검증 로직에 대한 unit test (잘못된 파일 거부 케이스 포함)
- 화면 위젯은 4개뿐이고 로직이 단순해 위젯 테스트는 Provider 목업을 이용한 최소 스모크
  테스트(빈 상태 렌더링, 카드 뒤집기 인터랙션)만 작성 — 전체 커버리지는 배제

## 8. 개발 환경

이 세션 기준 macOS 개발 환경에 Flutter SDK, Android SDK, Xcode가 설치되어 있지 않다.
구현 착수 전 아래가 필요하다:
- Flutter SDK (`brew install --cask flutter`)
- Android Studio + SDK (`brew install --cask android-studio`, 최초 실행 시 SDK 설치 마법사 완료)
- Xcode (App Store, iOS 빌드/시뮬레이터용)

## 9. 범위 밖

- Share Extension / Intent Filter 기반 import (OS 공유 시트에서 바로 열기)
- 클라우드 동기화, 로그인 (Phase C)
- SM-2 등 간격 반복 스케줄링 알고리즘 (Phase C)
- Home 화면 검색/필터링
