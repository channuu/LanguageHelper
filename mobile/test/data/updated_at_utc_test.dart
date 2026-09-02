// updated_at은 확장과 앱이 공유하는 유일한 충돌 판정 기준이고, 양쪽 머지
// 구현 모두 이 값을 '문자열로' 비교한다. 확장은 toISOString()으로 Z가 붙은
// UTC를 쓰므로, 앱이 로컬 시각(DateTime.now().toIso8601String(), Z 없음)을
// 쓰면 두 형식이 섞여 대소가 뒤집힌다. UTC 음수 지역에서는 앱이 방금 찍은
// 값이 확장의 옛 값보다 작아져 복습 기록이 되돌려진다.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:english_helper_app/data/database.dart';
import 'package:english_helper_app/data/models/sentence.dart';
import 'package:english_helper_app/data/models/word.dart';
import 'package:english_helper_app/data/repository.dart';
import 'package:english_helper_app/data/study_timer_repository.dart';

void main() {
  late LocalSQLiteRepository repo;
  late LocalStudyTimerRepository timerRepo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repo = LocalSQLiteRepository(
        openDb: () => openAppDatabase(inMemoryDatabasePath));
    timerRepo = LocalStudyTimerRepository(
        openDb: () => openAppDatabase(inMemoryDatabasePath));
  });

  tearDown(() async {
    await repo.close();
    await timerRepo.close();
  });

  const t0 = '2026-08-01T00:00:00.000Z';

  Word makeWord(String id) => Word(
        id: id, word: 'w', platform: 'youtube', contentTitle: 'T',
        contentId: 'v1', timestamp: 0, savedAt: t0, updatedAt: t0,
      );

  Sentence makeSentence(String id) => Sentence(
        id: id, original: 's', platform: 'youtube', contentTitle: 'T',
        contentId: 'v1', timestamp: 0, savedAt: t0, updatedAt: t0,
      );

  test('markWordReviewed는 updatedAt을 UTC로 쓴다', () async {
    await repo.saveWord(makeWord('w1'));
    await repo.markWordReviewed('w1');
    expect((await repo.getWords()).single.updatedAt, endsWith('Z'));
  });

  test('setWordReviewLevel은 updatedAt을 UTC로 쓴다', () async {
    await repo.saveWord(makeWord('w2'));
    await repo.setWordReviewLevel('w2', 3);
    expect((await repo.getWords()).single.updatedAt, endsWith('Z'));
  });

  test('markSentenceReviewed는 updatedAt을 UTC로 쓴다', () async {
    await repo.saveSentence(makeSentence('s1'));
    await repo.markSentenceReviewed('s1');
    expect((await repo.getSentences()).single.updatedAt, endsWith('Z'));
  });

  test('setSentenceReviewLevel은 updatedAt을 UTC로 쓴다', () async {
    await repo.saveSentence(makeSentence('s2'));
    await repo.setSentenceReviewLevel('s2', 2);
    expect((await repo.getSentences()).single.updatedAt, endsWith('Z'));
  });

  test('endSession은 updatedAt을 UTC로 쓴다', () async {
    await timerRepo.startSession();
    await timerRepo.endSession();
    expect((await timerRepo.getAllSessions()).single.updatedAt, endsWith('Z'));
  });

  test('setWeeklyGoal은 updatedAt을 UTC로 쓴다', () async {
    await timerRepo.setWeeklyGoal(300);
    expect((await timerRepo.getAllGoals()).single.updatedAt, endsWith('Z'));
  });
}
