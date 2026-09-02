# 후속 정리: 동기화 검증 이후 걷어낼 것들

설계 문서 `2026-08-29-firebase-cloud-sync-design.md` §8·§9는 클라우드 동기화가
검증된 **뒤에** 파일 기반 데이터 이동 경로를 걷어내라고 정해두었다.
17개 태스크 계획(`2026-08-29-firebase-cloud-sync.md`)은 타이머 동기화까지만
다루고 여기서 멈춘다 — 의도된 보류이지 누락이 아니다. 최종 브랜치 리뷰에서
"조용히 사라지지 않도록 따로 추적하라"는 지적을 받아 여기 남긴다.

**선행 조건**: 확장↔앱 왕복이 실기기에서 확인될 것(진행 원장의
OUTSTANDING 항목). 그 전에 걷어내면 되돌아갈 길이 없다.

## 확장

- [ ] `core/sqlite-export.js`와 라이브러리 패널의 "SQLite 내보내기" 버튼·안내문
- [ ] `vendor/sql-wasm.js` (지금도 콘텐츠 스크립트 4곳에 실린다 — `manifest.json`)
- [ ] 위 제거에 따른 `manifest.json` `content_scripts` 정리

## 앱

- [ ] `ImportScreen`과 가져오기 탭 (`features/import/`)
- [ ] `file_picker` 의존성
- [ ] `LearningRepository.mergeFromFile` / `LastImportSummary` 경로
- [ ] 설정 화면의 "DB 파일 경로" 행과 JSON 내보내기
- [ ] 하단 내비게이션 4탭 → 3탭 (홈/플래시카드/타이머/설정에서 가져오기 제외)

## 그 밖에

- [ ] 앱의 `FirestoreRemoteStore.list`는 컬렉션 전체를 매번 받는다.
      항목 수가 수천 개가 되면 `updated_at` 기준 증분 pull이 필요하다.
