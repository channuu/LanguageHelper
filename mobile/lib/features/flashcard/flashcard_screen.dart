import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/sentence.dart';
import '../../data/models/word.dart';
import '../../data/repository.dart';
import '../../data/review_schedule.dart';
import '../../shared/widgets/empty_state.dart';
import '../../theme/app_theme.dart';
import 'flashcard_item.dart';

enum _FlashcardMode { card, list }
enum _TypeFilter { all, wordOnly, sentenceOnly }

class FlashcardScreen extends StatefulWidget {
  const FlashcardScreen({super.key});

  @override
  State<FlashcardScreen> createState() => _FlashcardScreenState();
}

class _FlashcardScreenState extends State<FlashcardScreen> {
  List<FlashcardItem>? _queue;
  int _initialQueueLength = 0;
  bool _flipped = false;
  bool _graded = false;
  bool _wasCorrect = false;
  final _answerController = TextEditingController();

  bool _hadItemsInitially = false;

  _FlashcardMode _mode = _FlashcardMode.card;
  _TypeFilter _typeFilter = _TypeFilter.all;
  int? _listLevelFilter; // null = 전체

  LearningRepository? _repo;

  @override
  void initState() {
    super.initState();
    _loadQueue();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repo = context.read<LearningRepository>();
    if (!identical(repo, _repo)) {
      _repo?.removeListener(_onRepositoryChanged);
      _repo = repo;
      repo.addListener(_onRepositoryChanged);
    }
  }

  @override
  void dispose() {
    _repo?.removeListener(_onRepositoryChanged);
    _answerController.dispose();
    super.dispose();
  }

  void _onRepositoryChanged() {
    if (_queue == null || _queue!.isEmpty) {
      _loadQueue();
    }
  }

  List<Word> _allWords = [];
  List<Sentence> _allSentences = [];

  Future<void> _loadQueue() async {
    final repo = context.read<LearningRepository>();
    final words = await repo.getWords();
    final sentences = await repo.getSentences();
    _allWords = words;
    _allSentences = sentences;
    final dueItems = [
      if (_typeFilter != _TypeFilter.sentenceOnly)
        ...words
            .where((w) => isDueForReview(w.reviewLevel, w.nextReviewAt))
            .map(FlashcardItem.fromWord),
      if (_typeFilter != _TypeFilter.wordOnly)
        ...sentences
            .where((s) => isDueForReview(s.reviewLevel, s.nextReviewAt))
            .map(FlashcardItem.fromSentence),
    ]..shuffle(Random());
    if (!mounted) return;
    setState(() {
      _queue = dueItems;
      _initialQueueLength = dueItems.length;
      _hadItemsInitially = words.isNotEmpty || sentences.isNotEmpty;
      _flipped = false;
      _graded = false;
      _wasCorrect = false;
      _answerController.clear();
    });
  }

  void _setTypeFilter(_TypeFilter filter) {
    setState(() => _typeFilter = filter);
    _loadQueue();
  }

  List<FlashcardItem> get _listItems {
    final items = [
      if (_typeFilter != _TypeFilter.sentenceOnly) ..._allWords.map(FlashcardItem.fromWord),
      if (_typeFilter != _TypeFilter.wordOnly) ..._allSentences.map(FlashcardItem.fromSentence),
    ];
    if (_listLevelFilter == null) return items;
    return items.where((it) => it.reviewLevel == _listLevelFilter).toList();
  }

  void _again() {
    setState(() {
      final current = _queue!.removeAt(0);
      _queue!.add(current);
      _flipped = false;
      _graded = false;
      _wasCorrect = false;
      _answerController.clear();
    });
  }

  Future<void> _know() async {
    final repo = context.read<LearningRepository>();
    final current = _queue!.first;
    if (current.isWord) {
      await repo.markWordReviewed(current.id);
    } else {
      await repo.markSentenceReviewed(current.id);
    }
    setState(() {
      _queue!.removeAt(0);
      _flipped = false;
      _graded = false;
      _wasCorrect = false;
      _answerController.clear();
    });
  }

  void _submitAnswer() {
    final input = _answerController.text.trim();
    if (input.isEmpty) return;
    final current = _queue!.first;
    setState(() {
      _graded = true;
      _wasCorrect = input.toLowerCase() == current.correctAnswer.trim().toLowerCase();
    });
  }

  void _toggleFlip() {
    setState(() => _flipped = !_flipped);
  }

  @override
  Widget build(BuildContext context) {
    final queue = _queue;
    return Scaffold(
      appBar: AppBar(title: const Text('플래시카드')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Column(
              children: [
                _ModeToggle(
                  mode: _mode,
                  listCount: _allWords.length + _allSentences.length,
                  onCard: () => setState(() => _mode = _FlashcardMode.card),
                  onList: () => setState(() => _mode = _FlashcardMode.list),
                ),
                const SizedBox(height: 10),
                _TypeFilterRow(current: _typeFilter, onPick: _setTypeFilter),
              ],
            ),
          ),
          Expanded(
            child: queue == null
                ? const Center(child: CircularProgressIndicator())
                : _mode == _FlashcardMode.card
                    ? _buildCardMode(queue)
                    : _buildListMode(),
          ),
        ],
      ),
    );
  }

  Widget _buildCardMode(List<FlashcardItem> queue) {
    if (queue.isEmpty) {
      return EmptyState(
        message: _hadItemsInitially
            ? '오늘 복습 완료! 🎉'
            : '아직 저장된 항목이 없어요.\n크롬 확장 프로그램에서 단어나 문장을 저장해보세요!',
      );
    }
    final current = queue.first;
    final progress = _initialQueueLength == 0 ? 0.0 : 1 - (queue.length / _initialQueueLength);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        children: [
          _CardHeader(item: current),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: const Color(0xFFE5E8F0),
              valueColor: const AlwaysStoppedAnimation(AppColors.accent),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: GestureDetector(
              key: const ValueKey('flashcard-body'),
              onTap: _toggleFlip,
              child: Card(
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  side: const BorderSide(color: AppColors.border),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _flipped ? _CardBack(item: current) : _CardFront(item: current, promptSize: 24),
                ),
              ),
            ),
          ),
          if (!_flipped) ...[
            const SizedBox(height: 14),
            _AnswerInput(
              controller: _answerController,
              onSubmit: _submitAnswer,
              graded: _graded,
              wasCorrect: _wasCorrect,
              correctAnswer: current.correctAnswer,
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _again,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    side: const BorderSide(color: AppColors.borderStrong),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('다시'),
                ),
              ),
              if (_flipped) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _know,
                    style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    child: const Text('알아요'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildListMode() {
    final items = _listItems;
    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 7),
                      child: _levelChip(label: '전체', level: null),
                    ),
                    for (var lvl = 0; lvl <= kMaxReviewLevel; lvl++)
                      Padding(
                        padding: const EdgeInsets.only(right: 7),
                        child: _levelChip(label: kReviewLevelNames[lvl], level: lvl),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: items.isEmpty
                  ? const EmptyState(message: '해당 레벨의 항목이 없어요')
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                      itemCount: items.length,
                      itemBuilder: (context, index) => Padding(
                        padding: const EdgeInsets.only(bottom: 9),
                        child: _ListItemCard(
                          item: items[index],
                          onTap: () => _openEditSheet(items[index]),
                        ),
                      ),
                    ),
            ),
          ],
        ),
        Positioned(
          right: 20,
          bottom: 20,
          child: FloatingActionButton.extended(
            onPressed: () => _openEditSheet(null),
            backgroundColor: AppColors.accent,
            foregroundColor: AppColors.ink,
            icon: const Icon(Icons.add),
            label: const Text('추가'),
          ),
        ),
      ],
    );
  }

  Widget _levelChip({required String label, required int? level}) {
    final selected = _listLevelFilter == level;
    return ChoiceChip(
      key: ValueKey('level-chip-${level ?? 'all'}'),
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
      onSelected: (_) => setState(() => _listLevelFilter = level),
    );
  }

  void _openEditSheet(FlashcardItem? item) {
    // Wired up in Task 5.
  }
}

class _CardHeader extends StatelessWidget {
  final FlashcardItem item;
  const _CardHeader({required this.item});

  @override
  Widget build(BuildContext context) {
    final name = kReviewLevelNames[item.reviewLevel];
    final days = kReviewIntervalDays[item.reviewLevel];
    final gap = days == null ? '' : '$days일';
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.accentTint,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            name,
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              color: AppColors.accentInk,
            ),
          ),
        ),
        if (gap.isNotEmpty) ...[
          const SizedBox(width: 7),
          Text(gap, style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 11, color: AppColors.inkQuaternary)),
        ],
        const Spacer(),
        Text(
          '마지막 복습 ${item.lastReviewedAt == null ? '없음' : _shortDate(item.lastReviewedAt!)}',
          style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 11, color: AppColors.inkQuaternary),
        ),
      ],
    );
  }

  static String _shortDate(String iso) {
    final d = DateTime.parse(iso);
    return '${d.month}/${d.day}';
  }
}

class _CardFront extends StatelessWidget {
  final FlashcardItem item;
  final double promptSize;
  const _CardFront({required this.item, required this.promptSize});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            item.promptLabel,
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.12,
              color: AppColors.inkTertiary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            item.prompt,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppFonts.display,
              fontWeight: FontWeight.w600,
              fontSize: promptSize,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _CardBack extends StatelessWidget {
  final FlashcardItem item;
  const _CardBack({required this.item});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(item.backHeadline, style: const TextStyle(
          fontFamily: AppFonts.display, fontWeight: FontWeight.w600, fontSize: 26, color: AppColors.ink)),
        if (item.backSubtext.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(item.backSubtext, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.ink)),
        ],
        if (item.backDetail.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(item.backDetail, style: const TextStyle(fontSize: 13.5, color: AppColors.inkTertiary, height: 1.6)),
        ],
        if (item.backExample.isNotEmpty) ...[
          const SizedBox(height: 18),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 18),
          Text(item.backExample, style: const TextStyle(fontFamily: AppFonts.display, fontSize: 15, color: AppColors.inkSecondary, height: 1.55)),
        ],
      ],
    );
  }
}

class _AnswerInput extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSubmit;
  final bool graded;
  final bool wasCorrect;
  final String correctAnswer;

  const _AnswerInput({
    required this.controller,
    required this.onSubmit,
    required this.graded,
    required this.wasCorrect,
    required this.correctAnswer,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 58,
          padding: const EdgeInsets.only(left: 16, right: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderStrong, width: 1.5),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  onSubmitted: (_) => onSubmit(),
                  decoration: const InputDecoration(border: InputBorder.none, hintText: '답을 입력하세요'),
                  style: const TextStyle(fontFamily: AppFonts.display, fontSize: 16),
                ),
              ),
              IconButton(
                onPressed: onSubmit,
                icon: const Icon(Icons.arrow_forward),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.ink,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
        if (graded) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Row(
              children: [
                Text(
                  wasCorrect ? '정답!' : '오답',
                  style: TextStyle(
                    fontFamily: AppFonts.display,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                    color: wasCorrect ? AppColors.accentInk : AppColors.danger,
                  ),
                ),
                if (!wasCorrect) ...[
                  const SizedBox(width: 8),
                  Text('정답: $correctAnswer', style: const TextStyle(fontSize: 12.5, color: AppColors.inkTertiary)),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ModeToggle extends StatelessWidget {
  final _FlashcardMode mode;
  final int listCount;
  final VoidCallback onCard;
  final VoidCallback onList;

  const _ModeToggle({required this.mode, required this.listCount, required this.onCard, required this.onList});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: const Color(0xFFE9ECF3), borderRadius: BorderRadius.circular(11)),
      child: Row(
        children: [
          Expanded(child: _segment('카드', mode == _FlashcardMode.card, onCard)),
          Expanded(child: _segment('목록 $listCount', mode == _FlashcardMode.list, onList)),
        ],
      ),
    );
  }

  Widget _segment(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 34,
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppFonts.display,
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: selected ? AppColors.ink : AppColors.inkTertiary,
          ),
        ),
      ),
    );
  }
}

class _TypeFilterRow extends StatelessWidget {
  final _TypeFilter current;
  final void Function(_TypeFilter) onPick;
  const _TypeFilterRow({required this.current, required this.onPick});

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, _TypeFilter value) {
      final selected = current == value;
      return Padding(
        padding: const EdgeInsets.only(right: 7),
        child: ChoiceChip(
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
          onSelected: (_) => onPick(value),
        ),
      );
    }

    return Row(
      children: [
        chip('전체', _TypeFilter.all),
        chip('단어', _TypeFilter.wordOnly),
        chip('문장', _TypeFilter.sentenceOnly),
      ],
    );
  }
}

class _ListItemCard extends StatelessWidget {
  final FlashcardItem item;
  final VoidCallback onTap;
  const _ListItemCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.backHeadline, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5, color: AppColors.ink)),
                      if (item.backSubtext.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(item.backSubtext, style: const TextStyle(fontSize: 13, color: AppColors.inkSecondary)),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.accentTint, borderRadius: BorderRadius.circular(5)),
                  child: Text(
                    kReviewLevelNames[item.reviewLevel],
                    style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.accentInk),
                  ),
                ),
              ],
            ),
            if (item.backExample.isNotEmpty) ...[
              const SizedBox(height: 9),
              Container(
                padding: const EdgeInsets.only(left: 9),
                decoration: const BoxDecoration(border: Border(left: BorderSide(color: AppColors.border, width: 2))),
                child: Text(item.backExample, style: const TextStyle(fontSize: 12.5, color: AppColors.inkTertiary)),
              ),
            ],
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.only(top: 9),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFF0F2F7)))),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '마지막 복습 ${item.lastReviewedAt == null ? '없음' : _CardHeader._shortDate(item.lastReviewedAt!)}',
                      style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 11, color: AppColors.inkQuaternary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
