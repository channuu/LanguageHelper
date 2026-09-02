# 후속 정리: 동기화 검증 이후 걷어낼 것들

설계 문서 `2026-08-29-firebase-cloud-sync-design.md` §8·§9는 클라우드 동기화가
검증된 **뒤에** 파일 기반 데이터 이동 경로를 걷어내라고 정해두었다.
17개 태스크 계획(`2026-08-29-firebase-cloud-sync.md`)은 타이머 동기화까지만
다루고 여기서 멈춘다 — 의도된 보류이지 누락이 아니다. 최종 브랜치 리뷰에서
"조용히 사라지지 않도록 따로 추적하라"는 지적을 받아 여기 남긴다.

**선행 조건**: 확장↔앱 왕복이 실기기에서 확인될 것.
→ 2026-09-02 오후 충족. 단어 저장→앱 반영, 앱 삭제→확장 전파, 로그아웃 가드,
계정 전환 초기화, 오프라인 대기 표시까지 실기기에서 확인했다(진행 원장 참고).

## 확장 — 완료 (e5c92c4)

- [x] `core/sqlite-export.js`와 라이브러리 패널의 "SQLite 내보내기" 버튼·안내문
- [x] 설정 패널의 "저장 항목 내보내기 .sqlite" 버튼 (계획에 없던 두 번째 진입점)
- [x] `vendor/sql-wasm.js` / `vendor/sql-wasm.wasm`
- [x] `manifest.json` `content_scripts` 정리 (59→51개) 및 wasm의
      `web_accessible_resources` 항목 제거, 관련 CSS 제거

## 앱 — 완료 (e5c92c4, b7eb907)

- [x] `ImportScreen`과 가져오기 탭 (`features/import/`)
- [x] `file_picker` 의존성
- [x] `LearningRepository.mergeFromFile` / `LastImportSummary` 경로
      (`MergeResult`, `InvalidBackupFileException`, `getLastImportSummary`,
      `database.dart`의 `hasValidSchema`·컬럼 상수까지)
- [x] 설정 화면의 '데이터' 섹션(DB 파일 경로, 저장된 항목)
      — JSON 내보내기는 애초에 구현된 적이 없다. 스펙에만 있던 항목.
- [x] 하단 내비게이션 5탭 → 4탭 (홈/플래시카드/타이머/설정)
      — 계획에 "4탭 → 3탭"으로 적혀 있었으나 타이머 탭을 빠뜨린 오기였다.
- [x] 홈 빈 상태 문구에서 사라진 탭을 가리키던 안내 교체

## 목업 — 완료 (Claude Design 프로젝트, 2026-09-02)

- [x] `AppNav.dc.html` 4탭
- [x] `English Helper UI.dc.html`: 1f 아트보드의 가져오기 화면 제거,
      설정의 '데이터' 섹션 제거, 확장 패널 목업의 .sqlite 버튼 2개 제거,
      파일 다리를 계정 동기화로 설명하는 문구로 교체
      (새로 쓴 문구는 사용자 확인 필요)

## 남은 것

- [ ] 앱의 `FirestoreRemoteStore.list`는 컬렉션 전체를 매번 받는다.
      항목 수가 수천 개가 되면 `updated_at` 기준 증분 pull이 필요하다.
