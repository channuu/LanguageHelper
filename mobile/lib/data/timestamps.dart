/// updated_at 전용 시각 생성기.
///
/// 이 값은 확장(JS `new Date().toISOString()`)이 쓴 값과 **문자열로** 비교돼
/// 마지막 쓰기 승자를 가른다(cloud/merge.js, data/sync/merge.dart). 로컬
/// 시각을 쓰면 Dart가 Z를 붙이지 않아 두 형식이 섞이고, UTC 음수 지역에서는
/// 방금 찍은 값이 상대의 옛 값보다 작아져 복습 기록이 되돌려진다.
///
/// saved_at·last_reviewed_at·next_review_at처럼 화면에서 로컬 시각으로 읽는
/// 값에는 쓰지 않는다 — 그쪽은 비교 대상이 아니다.
String utcNowIso() => DateTime.now().toUtc().toIso8601String();
