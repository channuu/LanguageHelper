// ================================================================
// flutter_integration.dart
// Flutter 앱에서 Firebase Firestore와 연동하는 뼈대 코드
//
// pubspec.yaml 의존성:
//   firebase_core: ^2.24.2
//   firebase_auth: ^4.15.3
//   cloud_firestore: ^4.13.6
// ================================================================

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ── Firestore 데이터 모델 ──────────────────────────────────────
// 컬렉션: saved_sentences
// 문서 구조:
// {
//   userId:      String,
//   english:     String,   // 영어 원문
//   korean:      String,   // 한글 번역 (Phase 2에서 추가)
//   context:     String,   // 앞뒤 문맥 (선택)
//   source:      String,   // "youtube" | "netflix"
//   sourceUrl:   String,
//   videoTitle:  String,
//   timestamp:   Timestamp,
//   reviewCount: int,      // 복습 횟수
//   nextReviewAt: Timestamp | null   // 다음 복습 예정일 (SM-2)
// }

class SavedSentence {
  final String id;
  final String english;
  final String korean;
  final String source;
  final String videoTitle;
  final DateTime timestamp;
  final int reviewCount;
  final DateTime? nextReviewAt;

  SavedSentence({
    required this.id,
    required this.english,
    this.korean = '',
    required this.source,
    required this.videoTitle,
    required this.timestamp,
    this.reviewCount = 0,
    this.nextReviewAt,
  });

  factory SavedSentence.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SavedSentence(
      id:           doc.id,
      english:      data['english'] ?? '',
      korean:       data['korean'] ?? '',
      source:       data['source'] ?? '',
      videoTitle:   data['videoTitle'] ?? '',
      timestamp:    (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      reviewCount:  data['reviewCount'] ?? 0,
      nextReviewAt: (data['nextReviewAt'] as Timestamp?)?.toDate(),
    );
  }
}

// ── 문장 Repository ───────────────────────────────────────────
class SentenceRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get _userId => _auth.currentUser?.uid;

  // 실시간 스트림 — Flutter StreamBuilder와 바로 연결 가능
  Stream<List<SavedSentence>> sentencesStream() {
    if (_userId == null) return Stream.value([]);
    return _db
        .collection('saved_sentences')
        .where('userId', isEqualTo: _userId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(SavedSentence.fromFirestore).toList());
  }

  // 오늘 복습해야 할 문장만
  Stream<List<SavedSentence>> todayReviewStream() {
    if (_userId == null) return Stream.value([]);
    return _db
        .collection('saved_sentences')
        .where('userId', isEqualTo: _userId)
        .where('nextReviewAt', isLessThanOrEqualTo: Timestamp.now())
        .snapshots()
        .map((snap) => snap.docs.map(SavedSentence.fromFirestore).toList());
  }

  // SM-2 알고리즘 기반 복습 업데이트
  // quality: 0(완전히 모름) ~ 5(완벽히 앎)
  Future<void> updateReview(String docId, int quality) async {
    final doc = await _db.collection('saved_sentences').doc(docId).get();
    final data = doc.data()!;
    final reviewCount = (data['reviewCount'] ?? 0) + 1;

    // 간단한 간격 계산 (완전한 SM-2는 easiness factor 포함)
    final daysUntilNext = quality >= 4 ? reviewCount * 2 : 1;
    final nextReview = DateTime.now().add(Duration(days: daysUntilNext));

    await _db.collection('saved_sentences').doc(docId).update({
      'reviewCount': reviewCount,
      'nextReviewAt': Timestamp.fromDate(nextReview),
    });
  }
}

// ── 사용 예시 (Flutter Widget) ────────────────────────────────
//
// class SavedSentencesPage extends StatelessWidget {
//   final repo = SentenceRepository();
//
//   @override
//   Widget build(BuildContext context) {
//     return StreamBuilder<List<SavedSentence>>(
//       stream: repo.sentencesStream(),
//       builder: (context, snapshot) {
//         if (!snapshot.hasData) return CircularProgressIndicator();
//         final sentences = snapshot.data!;
//         return ListView.builder(
//           itemCount: sentences.length,
//           itemBuilder: (ctx, i) => SentenceCard(sentence: sentences[i]),
//         );
//       },
//     );
//   }
// }
