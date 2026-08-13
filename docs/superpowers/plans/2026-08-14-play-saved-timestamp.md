# Play Saved Timestamp Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users tap a saved word/sentence in the Phase B Flutter app's Home screen, see its full context in a detail screen, and — for YouTube-sourced items only — play the saved moment inline via an embedded YouTube player.

**Architecture:** A new `DetailItem` value type (mirroring the existing `FlashcardItem` pattern) normalizes `Word`/`Sentence` into one shape for display. A new `ItemDetailScreen` renders that shape and conditionally shows a `youtube_player_flutter` player when the source platform is YouTube and the content ID looks like a valid YouTube video ID. `HomeScreen`'s list tiles navigate to it on tap.

**Tech Stack:** Existing stack (provider, sqflite) plus a new dependency: `youtube_player_flutter` (official YouTube IFrame API wrapper, confirmed installable at v10.0.1 against this project's pubspec constraints).

## Global Constraints

- YouTube only — items where `platform != 'youtube'` never show a play button; this is a hide, not a disabled/grayed-out state (per the approved design, not a "not supported" toast).
- No schema changes — `Word`/`Sentence` already carry `platform`/`contentId`/`timestamp`; this feature only reads them.
- No separate route/full-screen transition for playback — the player renders inline within the detail screen, replacing the play button in place.
- Entry point is the Home screen's list tiles only — no play icon added directly on the list rows themselves.
- Widget test coverage stays minimal, matching the rest of Phase B: cover the two models' correct field mapping, the platform-gated button visibility, and the invalid-content-ID message — not exhaustive UI coverage. The `youtube_player_flutter` widget's internal playback behavior is out of scope for testing (third-party package).

---

### Task 1: DetailItem value type

**Files:**
- Create: `mobile/lib/features/home/detail_item.dart`
- Test: `mobile/test/features/home/detail_item_test.dart`

**Interfaces:**
- Consumes: `Word` (`mobile/lib/data/models/word.dart`), `Sentence` (`mobile/lib/data/models/sentence.dart`) — existing models, already have `platform`/`contentId`/`timestamp`/`contentTitle` fields plus `word`/`definition`/`sentence`/`translation` (Word) or `original`/`translation` (Sentence).
- Produces: `DetailItem` (`{id, headline, detail, platform, contentId, contentTitle, timestamp}` with `.fromWord`/`.fromSentence` factories) — used by Task 2's `ItemDetailScreen` and Task 3's `HomeScreen` navigation wiring.

- [ ] **Step 1: Write the failing test**

```dart
// mobile/test/features/home/detail_item_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:english_helper_app/data/models/sentence.dart';
import 'package:english_helper_app/data/models/word.dart';
import 'package:english_helper_app/features/home/detail_item.dart';

void main() {
  group('DetailItem.fromWord', () {
    test('maps word/definition/translation into headline/detail', () {
      final word = Word(
        id: 'w1',
        word: 'ephemeral',
        definition: 'lasting for a very short time',
        translation: '덧없는',
        platform: 'youtube',
        contentTitle: 'Some Video',
        contentId: 'dQw4w9WgXcQ',
        timestamp: 142.5,
        savedAt: '2026-08-14T00:00:00.000Z',
      );

      final item = DetailItem.fromWord(word);

      expect(item.id, 'w1');
      expect(item.headline, 'ephemeral');
      expect(item.detail, 'lasting for a very short time\n덧없는');
      expect(item.platform, 'youtube');
      expect(item.contentId, 'dQw4w9WgXcQ');
      expect(item.contentTitle, 'Some Video');
      expect(item.timestamp, 142.5);
    });

    test('omits empty definition/translation from detail', () {
      final word = Word(
        id: 'w2',
        word: 'brief',
        platform: 'netflix',
        contentTitle: 'Title',
        contentId: 'abc',
        timestamp: 10,
        savedAt: '2026-08-14T00:00:00.000Z',
      );

      final item = DetailItem.fromWord(word);

      expect(item.detail, '');
    });
  });

  group('DetailItem.fromSentence', () {
    test('maps original/translation into headline/detail', () {
      final sentence = Sentence(
        id: 's1',
        original: 'Nothing in life is ephemeral.',
        translation: '인생에서 덧없지 않은 것은 없다.',
        platform: 'youtube',
        contentTitle: 'Some Video',
        contentId: 'dQw4w9WgXcQ',
        timestamp: 142.5,
        savedAt: '2026-08-14T00:00:00.000Z',
      );

      final item = DetailItem.fromSentence(sentence);

      expect(item.id, 's1');
      expect(item.headline, 'Nothing in life is ephemeral.');
      expect(item.detail, '인생에서 덧없지 않은 것은 없다.');
      expect(item.platform, 'youtube');
      expect(item.contentId, 'dQw4w9WgXcQ');
      expect(item.contentTitle, 'Some Video');
      expect(item.timestamp, 142.5);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd mobile && flutter test test/features/home/detail_item_test.dart
```
Expected: FAIL — `mobile/lib/features/home/detail_item.dart` doesn't exist yet.

- [ ] **Step 3: Implement DetailItem**

```dart
// mobile/lib/features/home/detail_item.dart
import '../../data/models/sentence.dart';
import '../../data/models/word.dart';

class DetailItem {
  final String id;
  final String headline;
  final String detail;
  final String platform;
  final String contentId;
  final String contentTitle;
  final double timestamp;

  const DetailItem({
    required this.id,
    required this.headline,
    required this.detail,
    required this.platform,
    required this.contentId,
    required this.contentTitle,
    required this.timestamp,
  });

  factory DetailItem.fromWord(Word w) => DetailItem(
        id: w.id,
        headline: w.word,
        detail: [w.definition, w.translation].where((s) => s.isNotEmpty).join('\n'),
        platform: w.platform,
        contentId: w.contentId,
        contentTitle: w.contentTitle,
        timestamp: w.timestamp,
      );

  factory DetailItem.fromSentence(Sentence s) => DetailItem(
        id: s.id,
        headline: s.original,
        detail: s.translation,
        platform: s.platform,
        contentId: s.contentId,
        contentTitle: s.contentTitle,
        timestamp: s.timestamp,
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd mobile && flutter test test/features/home/detail_item_test.dart
```
Expected: `00:0X +3: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/home/detail_item.dart mobile/test/features/home/detail_item_test.dart
git commit -m "feat: add DetailItem value type normalizing Word/Sentence for detail display"
```

---

### Task 2: youtube_player_flutter dependency + ItemDetailScreen

**Files:**
- Modify: `mobile/pubspec.yaml`
- Create: `mobile/lib/features/home/item_detail_screen.dart`
- Test: `mobile/test/features/home/item_detail_screen_test.dart`

**Interfaces:**
- Consumes: `DetailItem` (Task 1), `youtube_player_flutter`'s `YoutubePlayer`/`YoutubePlayerController`/`YoutubePlayerFlags`/`YoutubePlayerBuilder` (or the package's actual top-level API — confirm exact class/constructor names against the installed v10.0.1 source before writing code, since plan text can drift from an evolving third-party package).
- Produces: `ItemDetailScreen` widget (`StatefulWidget`, takes a required `DetailItem` constructor param) — mounted by Task 3's `HomeScreen` navigation wiring.

- [ ] **Step 1: Add the youtube_player_flutter dependency**

```bash
cd mobile && flutter pub add youtube_player_flutter
```
Expected: `youtube_player_flutter` added under `dependencies:` in `pubspec.yaml` (confirmed installable at v10.0.1 against this project's constraints as of plan-writing time — if `flutter pub add` resolves to a materially different major version, read that version's actual API before proceeding, since the exact class names in Step 3 below may not match).

- [ ] **Step 2: Write the failing test**

```dart
// mobile/test/features/home/item_detail_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:english_helper_app/features/home/detail_item.dart';
import 'package:english_helper_app/features/home/item_detail_screen.dart';

DetailItem _youtubeItem({String contentId = 'dQw4w9WgXcQ'}) => DetailItem(
      id: 'w1',
      headline: 'ephemeral',
      detail: 'lasting for a very short time',
      platform: 'youtube',
      contentId: contentId,
      contentTitle: 'Some Video',
      timestamp: 142.5,
    );

DetailItem _netflixItem() => const DetailItem(
      id: 'w2',
      headline: 'brief',
      detail: '짧은',
      platform: 'netflix',
      contentId: '81234567',
      contentTitle: 'Some Show',
      timestamp: 10,
    );

void main() {
  Widget buildScreen(DetailItem item) {
    return MaterialApp(home: ItemDetailScreen(item: item));
  }

  testWidgets('shows headline, detail, and source info', (tester) async {
    await tester.pumpWidget(buildScreen(_youtubeItem()));
    await tester.pumpAndSettle();

    expect(find.text('ephemeral'), findsOneWidget);
    expect(find.text('lasting for a very short time'), findsOneWidget);
    expect(find.textContaining('Some Video'), findsOneWidget);
  });

  testWidgets('shows a play button for a valid YouTube item', (tester) async {
    await tester.pumpWidget(buildScreen(_youtubeItem()));
    await tester.pumpAndSettle();

    expect(find.text('재생하기'), findsOneWidget);
  });

  testWidgets('hides the play button for a non-YouTube item', (tester) async {
    await tester.pumpWidget(buildScreen(_netflixItem()));
    await tester.pumpAndSettle();

    expect(find.text('재생하기'), findsNothing);
  });

  testWidgets('shows an unplayable message for an invalid YouTube content ID', (tester) async {
    await tester.pumpWidget(buildScreen(_youtubeItem(contentId: 'not-a-valid-id')));
    await tester.pumpAndSettle();

    expect(find.text('재생하기'), findsNothing);
    expect(find.text('재생할 수 없는 항목입니다'), findsOneWidget);
  });

  testWidgets('tapping play swaps the button for an inline player', (tester) async {
    await tester.pumpWidget(buildScreen(_youtubeItem()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('재생하기'));
    await tester.pumpAndSettle();

    expect(find.text('재생하기'), findsNothing);
    expect(find.byType(YoutubePlayer), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

```bash
cd mobile && flutter test test/features/home/item_detail_screen_test.dart
```
Expected: FAIL — `mobile/lib/features/home/item_detail_screen.dart` doesn't exist yet.

- [ ] **Step 4: Implement ItemDetailScreen**

Before writing this file, read the installed `youtube_player_flutter` package's main export
(`~/.pub-cache/hosted/pub.dev/youtube_player_flutter-<version>/lib/youtube_player_flutter.dart`
plus its `src/` directory) to confirm the exact controller constructor signature and the
`YoutubePlayer` widget's required parameters — the code below reflects the package's
documented v10.x surface at plan-writing time, but a subsequent version bump could rename
`initialVideoId`/`YoutubePlayerFlags`/`startAt`. Adjust field/parameter names to match
whatever the installed version actually exports before treating a compile error here as a
bug in your own code.

```dart
// mobile/lib/features/home/item_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

import 'detail_item.dart';

class ItemDetailScreen extends StatefulWidget {
  final DetailItem item;

  const ItemDetailScreen({super.key, required this.item});

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  YoutubePlayerController? _controller;
  bool _playing = false;

  bool get _isValidYoutubeId {
    final id = widget.item.contentId;
    return RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id);
  }

  bool get _canPlay => widget.item.platform == 'youtube' && _isValidYoutubeId;

  void _startPlayback() {
    _controller = YoutubePlayerController(
      initialVideoId: widget.item.contentId,
      flags: YoutubePlayerFlags(
        autoPlay: true,
        startAt: widget.item.timestamp.toInt(),
      ),
    );
    setState(() => _playing = true);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  String _formatTimestamp(double seconds) {
    final total = seconds.toInt();
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Scaffold(
      appBar: AppBar(title: Text(item.headline)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(item.headline, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          if (item.detail.isNotEmpty) Text(item.detail),
          const SizedBox(height: 16),
          Text(
            '${item.platform} · ${item.contentTitle} · ${_formatTimestamp(item.timestamp)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          if (_playing && _controller != null)
            YoutubePlayer(controller: _controller!)
          else if (_canPlay)
            ElevatedButton(
              onPressed: _startPlayback,
              child: const Text('재생하기'),
            )
          else if (item.platform == 'youtube')
            const Text('재생할 수 없는 항목입니다'),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

```bash
cd mobile && flutter test test/features/home/item_detail_screen_test.dart
```
Expected: `00:0X +5: All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add mobile/pubspec.yaml mobile/pubspec.lock mobile/lib/features/home/item_detail_screen.dart mobile/test/features/home/item_detail_screen_test.dart
git commit -m "feat: add ItemDetailScreen with inline YouTube playback for saved timestamps"
```

---

### Task 3: Wire Home screen list taps to ItemDetailScreen

**Files:**
- Modify: `mobile/lib/features/home/home_screen.dart`
- Modify: `mobile/test/features/home/home_screen_test.dart`

**Interfaces:**
- Consumes: `DetailItem` (Task 1), `ItemDetailScreen` (Task 2).
- Produces: nothing further — this is the final integration point for this feature.

- [ ] **Step 1: Write the failing test**

Add to `mobile/test/features/home/home_screen_test.dart` (alongside its existing empty-state
test — read the current file first to match its existing `LocalSQLiteRepository`/`provider`
setup pattern exactly, including any `databaseFactoryFfiNoIsolate` substitution already
present there from earlier Phase B work):

```dart
  testWidgets('tapping a word list tile navigates to its detail screen', (tester) async {
    final repo = LocalSQLiteRepository(
      openDb: () => openAppDatabase(inMemoryDatabasePath),
    );
    await repo.saveWord(Word(
      id: 'w1',
      word: 'ephemeral',
      definition: 'lasting for a very short time',
      platform: 'youtube',
      contentTitle: 'Some Video',
      contentId: 'dQw4w9WgXcQ',
      timestamp: 142.5,
      savedAt: '2026-08-14T00:00:00.000Z',
    ));

    await tester.pumpWidget(
      ChangeNotifierProvider<LearningRepository>.value(
        value: repo,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('ephemeral'));
    await tester.pumpAndSettle();

    expect(find.text('재생하기'), findsOneWidget);
  });
```

(Add the corresponding `import 'package:english_helper_app/data/models/word.dart';` at the
top of the test file if not already present.)

- [ ] **Step 2: Run test to verify it fails**

```bash
cd mobile && flutter test test/features/home/home_screen_test.dart
```
Expected: FAIL — tapping the tile does nothing yet, so no navigation occurs and `재생하기` is never found.

- [ ] **Step 3: Wire up navigation in home_screen.dart**

In `mobile/lib/features/home/home_screen.dart`, add the import:

```dart
import 'detail_item.dart';
import 'item_detail_screen.dart';
```

In `_WordList`'s `ListTile` (inside the `itemBuilder`), add an `onTap`:

```dart
              child: ListTile(
                title: Text(word.word),
                subtitle: Text(
                  '${word.translation}\n${word.platform} · ${word.contentTitle}',
                ),
                isThreeLine: true,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ItemDetailScreen(item: DetailItem.fromWord(word)),
                  ),
                ),
              ),
```

In `_SentenceList`'s `ListTile`, the same pattern:

```dart
              child: ListTile(
                title: Text(sentence.original),
                subtitle: Text(
                  '${sentence.translation}\n${sentence.platform} · ${sentence.contentTitle}',
                ),
                isThreeLine: true,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ItemDetailScreen(item: DetailItem.fromSentence(sentence)),
                  ),
                ),
              ),
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd mobile && flutter test test/features/home/home_screen_test.dart
```
Expected: all pass (previous empty-state test + the new navigation test).

- [ ] **Step 5: Run the full suite**

```bash
cd mobile && flutter test
```
Expected: every test across the whole project (existing Phase B + Study Timer tests plus this feature's tests) passes, 0 failures.

- [ ] **Step 6: Run the analyzer**

```bash
cd mobile && flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add mobile/lib/features/home/home_screen.dart mobile/test/features/home/home_screen_test.dart
git commit -m "feat: navigate to ItemDetailScreen when tapping a Home list item"
```

---

### Task 4: Run on a real simulator/emulator

**Files:** none (verification-only task).

**Interfaces:** none — this task drives the already-built app, it doesn't produce anything later tasks depend on.

- [ ] **Step 1: Launch the iOS simulator**

```bash
open -a Simulator
xcrun simctl list devices available | grep -i "iPhone 17\""
xcrun simctl boot <device-UUID-from-above> 2>&1 || true
```

- [ ] **Step 2: Run the app**

```bash
cd mobile && flutter run -d <device-UUID>
```
Expected: app builds, installs, and launches normally with the existing 5-tab bottom nav.

- [ ] **Step 3: Manually verify the play-saved-timestamp flow**

In the running simulator (requires at least one YouTube-sourced word/sentence to already be
imported — if the local DB is empty, this step can only confirm the empty-state Home screen
renders correctly, and the play flow itself needs to wait until real data exists via the
Import tab or a manually-inserted test row):
1. If a YouTube-sourced item exists: tap it on the Home screen — confirm the detail screen
   shows headline, detail, and source line correctly.
2. Confirm the "재생하기" button is visible for the YouTube item.
3. Tap "재생하기" — confirm the YouTube player renders inline and starts playing from
   approximately the saved timestamp (not from 0:00).
4. If a non-YouTube-sourced item exists (e.g. imported from a Netflix-tagged word): tap it —
   confirm no play button appears anywhere on that detail screen.

- [ ] **Step 4: No commit** — this task only verifies Tasks 1–3's output runs; it makes no code changes.
