# 홈 화면 재설계(1c) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Flutter app's Home screen (`mobile/lib/features/home/home_screen.dart`) with the layout from Claude Design mockup §1c — search, platform filter chips, a segmented 단어/문장 toggle with counts, and restyled cards — while keeping existing swipe-to-delete and tap-to-detail behavior intact.

**Architecture:** Two small shared utilities (`formatTimestamp()`, `PlatformBadge`) get extracted/created first so the screen rewrite can consume them. `HomeScreen` converts from `StatelessWidget` to `StatefulWidget`: it loads the full word/sentence lists once in `initState`, then applies search/platform filters client-side on every rebuild (the repository has no server-side filtering — see spec §3).

**Tech Stack:** Flutter/Dart, `provider` for `LearningRepository` access, existing `sqflite`-backed `LocalSQLiteRepository`, `flutter_test` + `sqflite_common_ffi` for widget tests.

## Global Constraints

- `LearningRepository.getWords()`/`getSentences()` take no parameters and always return the full list — do not change this interface (spec §3).
- Platform badges are the only UI element allowed a non-grayscale color; everything else uses the `AppColors` ink scale (spec §4, design system principle from mockup §1a).
- "마지막 가져오기" date display is explicitly out of scope (spec §8) — do not add it.
- Existing swipe-to-delete (`Dismissible`) and tap-to-navigate-to-`ItemDetailScreen` behavior must be preserved exactly (spec §5).
- Use `Color.withValues(alpha: ...)` (not the deprecated `withOpacity`) for any color-with-opacity in new code — this Flutter version (3.44.8) flags `withOpacity` as deprecated.

---

### Task 1: Shared timestamp formatter

**Files:**
- Create: `mobile/lib/shared/format/timestamp_format.dart`
- Modify: `mobile/lib/features/home/item_detail_screen.dart:41-46` (remove private `_formatTimestamp`, use the shared one)
- Test: `mobile/test/shared/format/timestamp_format_test.dart`

**Interfaces:**
- Produces: `String formatTimestamp(double seconds)` — top-level function, e.g. `formatTimestamp(142.5) == '2:22'`. Later tasks (Task 3) import and call this.

- [ ] **Step 1: Write the failing test**

Create `mobile/test/shared/format/timestamp_format_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:english_helper_app/shared/format/timestamp_format.dart';

void main() {
  test('formats whole seconds under a minute', () {
    expect(formatTimestamp(0), '0:00');
    expect(formatTimestamp(59), '0:59');
  });

  test('formats minutes and seconds with zero-padded seconds', () {
    expect(formatTimestamp(60), '1:00');
    expect(formatTimestamp(142.5), '2:22');
  });

  test('truncates fractional seconds', () {
    expect(formatTimestamp(9.9), '0:09');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test test/shared/format/timestamp_format_test.dart`
Expected: FAIL — `Error: Not found: 'package:english_helper_app/shared/format/timestamp_format.dart'`

- [ ] **Step 3: Write the implementation**

Create `mobile/lib/shared/format/timestamp_format.dart`:

```dart
/// Formats a duration in seconds as `m:ss` (minutes not zero-padded,
/// seconds zero-padded to 2 digits), e.g. `formatTimestamp(142.5) == '2:22'`.
String formatTimestamp(double seconds) {
  final total = seconds.toInt();
  final m = total ~/ 60;
  final s = total % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd mobile && flutter test test/shared/format/timestamp_format_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: Replace the duplicate in `item_detail_screen.dart`**

In `mobile/lib/features/home/item_detail_screen.dart`, add the import:

```dart
import '../../shared/format/timestamp_format.dart';
```

Remove the private method (lines 41-46):

```dart
  String _formatTimestamp(double seconds) {
    final total = seconds.toInt();
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
```

Change its one call site (currently `_formatTimestamp(item.timestamp)`) to `formatTimestamp(item.timestamp)`.

- [ ] **Step 6: Run the existing item-detail tests to confirm no regression**

Run: `cd mobile && flutter test test/features/home/item_detail_screen_test.dart`
Expected: PASS (5 tests) — none of them assert on the exact timestamp string, so this is a pure refactor.

- [ ] **Step 7: Commit**

```bash
cd mobile
git add lib/shared/format/timestamp_format.dart lib/features/home/item_detail_screen.dart test/shared/format/timestamp_format_test.dart
git commit -m "refactor: extract shared formatTimestamp() utility"
```

---

### Task 2: `PlatformBadge` shared widget

**Files:**
- Create: `mobile/lib/shared/widgets/platform_badge.dart`
- Test: `mobile/test/shared/widgets/platform_badge_test.dart`

**Interfaces:**
- Consumes: `AppColors.inkTertiary` from `mobile/lib/theme/app_theme.dart` (already exists on this branch).
- Produces: `class PlatformBadge extends StatelessWidget` with constructor `PlatformBadge({super.key, required String platform})`. Later tasks (Task 3) import and use `PlatformBadge(platform: word.platform)`.

- [ ] **Step 1: Write the failing test**

Create `mobile/test/shared/widgets/platform_badge_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:english_helper_app/shared/widgets/platform_badge.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('shows YouTube label for youtube platform', (tester) async {
    await tester.pumpWidget(wrap(const PlatformBadge(platform: 'youtube')));
    expect(find.text('YouTube'), findsOneWidget);
  });

  testWidgets('shows Netflix label for netflix platform', (tester) async {
    await tester.pumpWidget(wrap(const PlatformBadge(platform: 'netflix')));
    expect(find.text('Netflix'), findsOneWidget);
  });

  testWidgets('shows Disney+ label for disney platform', (tester) async {
    await tester.pumpWidget(wrap(const PlatformBadge(platform: 'disney')));
    expect(find.text('Disney+'), findsOneWidget);
  });

  testWidgets('shows 쿠팡플레이 label for coupang platform', (tester) async {
    await tester.pumpWidget(wrap(const PlatformBadge(platform: 'coupang')));
    expect(find.text('쿠팡플레이'), findsOneWidget);
  });

  testWidgets('falls back to the raw platform string for an unknown platform', (tester) async {
    await tester.pumpWidget(wrap(const PlatformBadge(platform: 'vimeo')));
    expect(find.text('vimeo'), findsOneWidget);
  });

  testWidgets('platform match is case-insensitive', (tester) async {
    await tester.pumpWidget(wrap(const PlatformBadge(platform: 'YouTube')));
    expect(find.text('YouTube'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test test/shared/widgets/platform_badge_test.dart`
Expected: FAIL — `Error: Not found: 'package:english_helper_app/shared/widgets/platform_badge.dart'`

- [ ] **Step 3: Write the implementation**

Create `mobile/lib/shared/widgets/platform_badge.dart`:

```dart
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class _BadgeStyle {
  final String label;
  final Color bg;
  final Color fg;
  const _BadgeStyle({required this.label, required this.bg, required this.fg});
}

/// Small colored pill showing a source platform (YouTube/Netflix/etc).
///
/// This is the one UI element allowed a non-grayscale color under the
/// design system's "ink scale everywhere except platform badges" rule
/// (mockup §1a).
class PlatformBadge extends StatelessWidget {
  final String platform;

  const PlatformBadge({super.key, required this.platform});

  static const Map<String, _BadgeStyle> _styles = {
    'youtube': _BadgeStyle(label: 'YouTube', bg: Color(0x1AFF0000), fg: Color(0xFFCC0000)),
    'netflix': _BadgeStyle(label: 'Netflix', bg: Color(0x1AE50914), fg: Color(0xFFB0060F)),
    'disney': _BadgeStyle(label: 'Disney+', bg: Color(0x1A0063E5), fg: Color(0xFF0050B8)),
    'coupang': _BadgeStyle(label: '쿠팡플레이', bg: Color(0x1A00C73C), fg: Color(0xFF00A030)),
  };

  @override
  Widget build(BuildContext context) {
    final style = _styles[platform.toLowerCase()] ??
        _BadgeStyle(label: platform, bg: const Color(0x14454D5E), fg: AppColors.inkTertiary);
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

- [ ] **Step 4: Run test to verify it passes**

Run: `cd mobile && flutter test test/shared/widgets/platform_badge_test.dart`
Expected: PASS (6 tests)

- [ ] **Step 5: Commit**

```bash
cd mobile
git add lib/shared/widgets/platform_badge.dart test/shared/widgets/platform_badge_test.dart
git commit -m "feat: add shared PlatformBadge widget"
```

---

### Task 3: Home screen rewrite

**Files:**
- Modify: `mobile/lib/features/home/home_screen.dart` (full rewrite)
- Test: `mobile/test/features/home/home_screen_test.dart` (extend existing file — keep its 2 existing tests passing, add new ones)

**Interfaces:**
- Consumes: `formatTimestamp(double) -> String` from `mobile/lib/shared/format/timestamp_format.dart` (Task 1). `PlatformBadge({required String platform})` from `mobile/lib/shared/widgets/platform_badge.dart` (Task 2). `AppColors`/`AppFonts` from `mobile/lib/theme/app_theme.dart` (already on branch). `DetailItem.fromWord`/`.fromSentence`, `ItemDetailScreen`, `EmptyState`, `LearningRepository` — all unchanged, already used by the current `home_screen.dart`.
- Produces: `HomeScreen` remains a public widget with a no-arg const constructor (`const HomeScreen({super.key})`) — same public API as before, so no caller elsewhere needs to change (`app.dart` already does `const HomeScreen()`).

- [ ] **Step 1: Write the failing tests (append to the existing test file)**

Replace the full contents of `mobile/test/features/home/home_screen_test.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:english_helper_app/data/database.dart';
import 'package:english_helper_app/data/models/sentence.dart';
import 'package:english_helper_app/data/models/word.dart';
import 'package:english_helper_app/data/repository.dart';
import 'package:english_helper_app/features/home/home_screen.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    // Use the no-isolate FFI factory: the isolate-based `databaseFactoryFfi`
    // communicates via a background Isolate, whose messages never get
    // flushed inside flutter_test's FakeAsync zone (used by testWidgets),
    // so a FutureBuilder awaiting a query would hang forever under
    // pumpAndSettle. The no-isolate variant runs queries synchronously in
    // zone, which FakeAsync can flush like any other Future.
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  Future<LocalSQLiteRepository> makeRepo() async {
    final repo = LocalSQLiteRepository(
      openDb: () => openAppDatabase(inMemoryDatabasePath),
    );
    return repo;
  }

  Widget buildApp(LearningRepository repo) {
    return ChangeNotifierProvider<LearningRepository>.value(
      value: repo,
      child: const MaterialApp(home: HomeScreen()),
    );
  }

  testWidgets('shows empty state when there are no saved items', (tester) async {
    final repo = await makeRepo();

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('아직 저장된 항목이 없어요'), findsOneWidget);
  });

  testWidgets('tapping a word list tile navigates to its detail screen', (tester) async {
    final repo = await makeRepo();
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

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ephemeral'));
    await tester.pumpAndSettle();

    expect(find.text('재생하기'), findsOneWidget);
  });

  testWidgets('word/sentence segment toggle shows correct counts', (tester) async {
    final repo = await makeRepo();
    await repo.saveWord(Word(
      id: 'w1',
      word: 'ephemeral',
      platform: 'youtube',
      contentTitle: 'V',
      contentId: 'dQw4w9WgXcQ',
      timestamp: 0,
      savedAt: '2026-08-14T00:00:00.000Z',
    ));
    await repo.saveSentence(Sentence(
      id: 's1',
      original: 'Nothing in life is ephemeral.',
      platform: 'youtube',
      contentTitle: 'V',
      contentId: 'dQw4w9WgXcQ',
      timestamp: 0,
      savedAt: '2026-08-14T00:00:00.000Z',
    ));
    await repo.saveSentence(Sentence(
      id: 's2',
      original: 'Another saved line.',
      platform: 'netflix',
      contentTitle: 'W',
      contentId: '81234567',
      timestamp: 0,
      savedAt: '2026-08-14T00:00:00.000Z',
    ));

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();

    expect(find.text('1'), findsOneWidget); // 단어 count
    expect(find.text('2'), findsOneWidget); // 문장 count
  });

  testWidgets('platform filter chip narrows the word list', (tester) async {
    final repo = await makeRepo();
    await repo.saveWord(Word(
      id: 'w1',
      word: 'ephemeral',
      platform: 'youtube',
      contentTitle: 'V1',
      contentId: 'dQw4w9WgXcQ',
      timestamp: 0,
      savedAt: '2026-08-14T00:00:00.000Z',
    ));
    await repo.saveWord(Word(
      id: 'w2',
      word: 'brief',
      platform: 'netflix',
      contentTitle: 'V2',
      contentId: '81234567',
      timestamp: 0,
      savedAt: '2026-08-14T00:00:00.000Z',
    ));

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();

    expect(find.text('ephemeral'), findsOneWidget);
    expect(find.text('brief'), findsOneWidget);

    await tester.tap(find.text('netflix'));
    await tester.pumpAndSettle();

    expect(find.text('ephemeral'), findsNothing);
    expect(find.text('brief'), findsOneWidget);
  });

  testWidgets('search narrows the word list by headline substring', (tester) async {
    final repo = await makeRepo();
    await repo.saveWord(Word(
      id: 'w1',
      word: 'ephemeral',
      platform: 'youtube',
      contentTitle: 'V1',
      contentId: 'dQw4w9WgXcQ',
      timestamp: 0,
      savedAt: '2026-08-14T00:00:00.000Z',
    ));
    await repo.saveWord(Word(
      id: 'w2',
      word: 'brief',
      platform: 'youtube',
      contentTitle: 'V2',
      contentId: 'dQw4w9WgXcQ',
      timestamp: 0,
      savedAt: '2026-08-14T00:00:00.000Z',
    ));

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ephem');
    await tester.pumpAndSettle();

    expect(find.text('ephemeral'), findsOneWidget);
    expect(find.text('brief'), findsNothing);
  });

  testWidgets('search with no matches shows the no-results empty state', (tester) async {
    final repo = await makeRepo();
    await repo.saveWord(Word(
      id: 'w1',
      word: 'ephemeral',
      platform: 'youtube',
      contentTitle: 'V1',
      contentId: 'dQw4w9WgXcQ',
      timestamp: 0,
      savedAt: '2026-08-14T00:00:00.000Z',
    ));

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'zzz_no_match');
    await tester.pumpAndSettle();

    expect(find.text('검색 결과가 없어요'), findsOneWidget);
  });

  testWidgets('swipe still deletes a word', (tester) async {
    final repo = await makeRepo();
    await repo.saveWord(Word(
      id: 'w1',
      word: 'ephemeral',
      platform: 'youtube',
      contentTitle: 'V1',
      contentId: 'dQw4w9WgXcQ',
      timestamp: 0,
      savedAt: '2026-08-14T00:00:00.000Z',
    ));

    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();

    await tester.drag(find.text('ephemeral'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.text('ephemeral'), findsNothing);
    expect(await repo.getWords(), isEmpty);
  });
}
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `cd mobile && flutter test test/features/home/home_screen_test.dart`
Expected: the 2 pre-existing tests still PASS against the old implementation; the 5 new tests FAIL (no segment-toggle counts, no filter chips, no search icon in the current UI).

- [ ] **Step 3: Write the implementation**

Replace the full contents of `mobile/lib/features/home/home_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/sentence.dart';
import '../../data/models/word.dart';
import '../../data/repository.dart';
import '../../shared/format/timestamp_format.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/platform_badge.dart';
import '../../theme/app_theme.dart';
import 'detail_item.dart';
import 'item_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _loaded = false;
  List<Word> _words = [];
  List<Sentence> _sentences = [];

  int _tab = 0; // 0 = 단어, 1 = 문장
  bool _searching = false;
  final _searchController = TextEditingController();
  String _query = '';
  String? _platformFilter; // null = 전체

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = context.read<LearningRepository>();
    final words = await repo.getWords();
    final sentences = await repo.getSentences();
    if (!mounted) return;
    setState(() {
      _words = words;
      _sentences = sentences;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _availablePlatforms {
    final platforms = <String>{
      ..._words.map((w) => w.platform),
      ..._sentences.map((s) => s.platform),
    }..removeWhere((p) => p.isEmpty);
    return platforms.toList()..sort();
  }

  bool _matchesQuery(String headline, String body) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return headline.toLowerCase().contains(q) || body.toLowerCase().contains(q);
  }

  List<Word> get _filteredWords => _words.where((w) {
        if (_platformFilter != null && w.platform != _platformFilter) return false;
        return _matchesQuery(w.word, '${w.translation} ${w.definition}');
      }).toList();

  List<Sentence> get _filteredSentences => _sentences.where((s) {
        if (_platformFilter != null && s.platform != _platformFilter) return false;
        return _matchesQuery(s.original, s.translation);
      }).toList();

  Future<void> _deleteWord(String id) async {
    await context.read<LearningRepository>().deleteWord(id);
    setState(() => _words.removeWhere((w) => w.id == id));
  }

  Future<void> _deleteSentence(String id) async {
    await context.read<LearningRepository>().deleteSentence(id);
    setState(() => _sentences.removeWhere((s) => s.id == id));
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final totalCount = _words.length + _sentences.length;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: _searching ? _buildSearchField() : _buildHeader(totalCount),
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildSegmentToggle(),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: _buildFilterChips(),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: _tab == 0 ? _buildWordList(_filteredWords) : _buildSentenceList(_filteredSentences),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(int totalCount) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('저장한 표현', style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 6),
              Text('$totalCount개', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        IconButton(
          onPressed: () => setState(() => _searching = true),
          icon: const Icon(Icons.search),
          tooltip: '검색',
        ),
      ],
    );
  }

  Widget _buildSearchField() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchController,
            autofocus: true,
            decoration: const InputDecoration(hintText: '검색'),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        TextButton(
          onPressed: () => setState(() {
            _searching = false;
            _query = '';
            _searchController.clear();
          }),
          child: const Text('취소'),
        ),
      ],
    );
  }

  Widget _buildSegmentToggle() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFE9ECF3),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SegmentButton(
              label: '단어',
              count: _words.length,
              selected: _tab == 0,
              onTap: () => setState(() => _tab = 0),
            ),
          ),
          Expanded(
            child: _SegmentButton(
              label: '문장',
              count: _sentences.length,
              selected: _tab == 1,
              onTap: () => setState(() => _tab = 1),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildFilterChips() {
    return [
      Padding(
        padding: const EdgeInsets.only(right: 7),
        child: _buildChip(label: '전체', value: null),
      ),
      for (final p in _availablePlatforms)
        Padding(
          padding: const EdgeInsets.only(right: 7),
          child: _buildChip(label: p, value: p),
        ),
    ];
  }

  Widget _buildChip({required String label, required String? value}) {
    final selected = _platformFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      shape: const StadiumBorder(),
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.ink,
      side: BorderSide(color: selected ? AppColors.ink : AppColors.border),
      labelStyle: TextStyle(
        fontFamily: AppFonts.display,
        fontWeight: FontWeight.w600,
        fontSize: 12,
        color: selected ? Colors.white : AppColors.inkSecondary,
      ),
      onSelected: (_) => setState(() => _platformFilter = value),
    );
  }

  Widget _buildWordList(List<Word> words) {
    if (words.isEmpty) {
      return EmptyState(message: _emptyMessage(hasAny: _words.isNotEmpty));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      itemCount: words.length,
      itemBuilder: (context, index) {
        final word = words[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Dismissible(
            key: ValueKey(word.id),
            direction: DismissDirection.endToStart,
            background: Container(color: AppColors.danger),
            onDismissed: (_) => _deleteWord(word.id),
            child: _WordCard(
              word: word,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ItemDetailScreen(item: DetailItem.fromWord(word)),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSentenceList(List<Sentence> sentences) {
    if (sentences.isEmpty) {
      return EmptyState(message: _emptyMessage(hasAny: _sentences.isNotEmpty));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      itemCount: sentences.length,
      itemBuilder: (context, index) {
        final sentence = sentences[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Dismissible(
            key: ValueKey(sentence.id),
            direction: DismissDirection.endToStart,
            background: Container(color: AppColors.danger),
            onDismissed: (_) => _deleteSentence(sentence.id),
            child: _SentenceCard(
              sentence: sentence,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ItemDetailScreen(item: DetailItem.fromSentence(sentence)),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _emptyMessage({required bool hasAny}) {
    return hasAny ? '검색 결과가 없어요' : '아직 저장된 항목이 없어요. Import 탭에서 불러오세요';
  }
}

class _SegmentButton extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _SegmentButton({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.ink : AppColors.inkTertiary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: AppFonts.display,
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
                color: color,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 11.5,
                color: color.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WordCard extends StatelessWidget {
  final Word word;
  final VoidCallback onTap;

  const _WordCard({required this.word, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(15, 14, 15, 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              word.word,
              style: const TextStyle(
                fontFamily: AppFonts.display,
                fontWeight: FontWeight.w700,
                fontSize: 20,
                color: AppColors.ink,
              ),
            ),
            if (word.translation.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(word.translation, style: const TextStyle(fontSize: 13.5, color: AppColors.ink)),
            ],
            if (word.definition.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                word.definition,
                style: const TextStyle(fontSize: 12, color: AppColors.inkTertiary, height: 1.4),
              ),
            ],
            if (word.sentence.isNotEmpty) ...[
              const SizedBox(height: 9),
              Container(
                padding: const EdgeInsets.only(left: 10),
                decoration: const BoxDecoration(
                  border: Border(left: BorderSide(color: AppColors.border, width: 2)),
                ),
                child: Text(
                  word.sentence,
                  style: const TextStyle(fontSize: 13, color: AppColors.inkSecondary, height: 1.4),
                ),
              ),
            ],
            const SizedBox(height: 11),
            _CardFooter(
              platform: word.platform,
              contentTitle: word.contentTitle,
              timestamp: word.timestamp,
            ),
          ],
        ),
      ),
    );
  }
}

class _SentenceCard extends StatelessWidget {
  final Sentence sentence;
  final VoidCallback onTap;

  const _SentenceCard({required this.sentence, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              sentence.original,
              style: const TextStyle(
                fontFamily: AppFonts.display,
                fontSize: 16.5,
                height: 1.5,
                color: AppColors.ink,
              ),
            ),
            if (sentence.translation.isNotEmpty) ...[
              const SizedBox(height: 7),
              Text(
                sentence.translation,
                style: const TextStyle(fontSize: 13, color: AppColors.inkSecondary, height: 1.6),
              ),
            ],
            const SizedBox(height: 11),
            _CardFooter(
              platform: sentence.platform,
              contentTitle: sentence.contentTitle,
              timestamp: sentence.timestamp,
            ),
          ],
        ),
      ),
    );
  }
}

class _CardFooter extends StatelessWidget {
  final String platform;
  final String contentTitle;
  final double timestamp;

  const _CardFooter({
    required this.platform,
    required this.contentTitle,
    required this.timestamp,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFF0F2F7))),
      ),
      child: Row(
        children: [
          PlatformBadge(platform: platform),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              contentTitle,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: const TextStyle(fontSize: 11.5, color: AppColors.inkTertiary),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.accentTint,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              formatTimestamp(timestamp),
              style: const TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 11.5,
                color: AppColors.accentInk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd mobile && flutter test test/features/home/home_screen_test.dart`
Expected: PASS (8 tests total — the 2 pre-existing plus 6 new).

- [ ] **Step 5: Run the full test suite and analyzer to check for regressions**

Run: `cd mobile && flutter analyze && flutter test`
Expected: `flutter analyze` reports no issues; `flutter test` passes with no failures anywhere (this touches a shared screen other tests may indirectly exercise, e.g. `test/main_test.dart`'s bottom-navigation test).

- [ ] **Step 6: Commit**

```bash
cd mobile
git add lib/features/home/home_screen.dart test/features/home/home_screen_test.dart
git commit -m "feat: redesign Home screen per mockup §1c (search, filters, cards)"
```

---

## Self-Review Notes

- **Spec coverage:** §3 (client-side filtering, no repo API change) → Task 3. §4 (`PlatformBadge`, `formatTimestamp`) → Tasks 1-2. §5 (screen structure: header/search, segment toggle, filter chips, cards, empty states) → Task 3. §6 (error handling: no-match empty state, unknown platform fallback) → Task 3 test "search with no matches" + Task 2 test "falls back to the raw platform string". §7 (all listed test cases) → covered across Task 1-3 test files. §8 (out of scope items) → none implemented, confirmed by omission.
- **Placeholder scan:** none found — every step has literal code and exact commands.
- **Type consistency:** `formatTimestamp(double) -> String` matches its Task 1 signature everywhere it's called in Task 3. `PlatformBadge({required String platform})` matches its Task 2 constructor everywhere it's used in Task 3. `HomeScreen`'s public constructor signature (`const HomeScreen({super.key})`) is unchanged from before, so `app.dart`'s `const HomeScreen()` call site needs no edit.
