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

  LearningRepository? _repo;

  @override
  void initState() {
    super.initState();
    _load();
    _repo = context.read<LearningRepository>()..addListener(_onRepoChanged);
  }

  void _onRepoChanged() {
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
    _repo?.removeListener(_onRepoChanged);
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
      selectedColor: AppColors.accent,
      side: BorderSide(color: selected ? Colors.transparent : AppColors.border),
      labelStyle: TextStyle(
        fontFamily: AppFonts.display,
        fontWeight: FontWeight.w600,
        fontSize: 12,
        color: selected ? AppColors.ink : AppColors.inkSecondary,
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
    return hasAny ? '검색 결과가 없어요' : '아직 저장된 항목이 없어요. 브라우저에서 단어를 저장해 보세요';
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
          color: selected ? AppColors.accent : Colors.transparent,
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
