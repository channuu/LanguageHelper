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

// Dart's `_`-prefixed privacy is per-file, so this can't import
// study_timer_repository.dart's identical private _generateId() — a small
// duplicate is simpler than exporting a cross-feature utility for 3 lines.
String _generateId() {
  final rand = Random();
  return List.generate(16, (_) => rand.nextInt(16).toRadixString(16)).join();
}

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
      selectedColor: AppColors.accent,
      side: BorderSide(color: selected ? Colors.transparent : AppColors.border),
      labelStyle: TextStyle(
        fontFamily: AppFonts.display,
        fontWeight: FontWeight.w600,
        fontSize: 12,
        color: selected ? AppColors.ink : AppColors.inkSecondary,
      ),
      onSelected: (_) => setState(() => _listLevelFilter = level),
    );
  }

  void _openEditSheet(FlashcardItem? item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditItemSheet(
        item: item,
        onSaved: _loadQueue,
      ),
    );
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
          color: selected ? AppColors.accent : Colors.transparent,
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
          selectedColor: AppColors.accent,
          side: BorderSide(color: selected ? Colors.transparent : AppColors.border),
          labelStyle: TextStyle(
            fontFamily: AppFonts.display,
            fontWeight: FontWeight.w600,
            fontSize: 12,
            color: selected ? AppColors.ink : AppColors.inkSecondary,
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

class _EditItemSheet extends StatefulWidget {
  final FlashcardItem? item; // null = creating a new item
  final VoidCallback onSaved;

  const _EditItemSheet({required this.item, required this.onSaved});

  @override
  State<_EditItemSheet> createState() => _EditItemSheetState();
}

class _EditItemSheetState extends State<_EditItemSheet> {
  late bool _isWord;
  late final TextEditingController _enController;
  late final TextEditingController _koController;
  late final TextEditingController _exController;
  late int _level;

  bool get _isNew => widget.item == null;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _isWord = item?.isWord ?? true;
    _enController = TextEditingController(text: item?.backHeadline ?? '');
    _koController = TextEditingController(text: item?.backSubtext ?? '');
    _exController = TextEditingController(text: item?.backExample ?? '');
    _level = item?.reviewLevel ?? 0;
  }

  @override
  void dispose() {
    _enController.dispose();
    _koController.dispose();
    _exController.dispose();
    super.dispose();
  }

  Future<void> _pickLevel(int level) async {
    setState(() => _level = level);
    final item = widget.item;
    if (item == null) return; // new item: level is only saved when 저장 is tapped
    final repo = context.read<LearningRepository>();
    if (item.isWord) {
      await repo.setWordReviewLevel(item.id, level);
    } else {
      await repo.setSentenceReviewLevel(item.id, level);
    }
  }

  Future<void> _save() async {
    final repo = context.read<LearningRepository>();
    final en = _enController.text.trim();
    final ko = _koController.text.trim();
    if (en.isEmpty) return;

    if (_isWord) {
      final existing = widget.item;
      if (existing != null) {
        final currentWords = await repo.getWords();
        Word? currentWord;
        for (final w in currentWords) {
          if (w.id == existing.id) {
            currentWord = w;
            break;
          }
        }
        if (currentWord == null) {
          widget.onSaved();
          if (mounted) Navigator.of(context).pop();
          return;
        }
        await repo.saveWord(currentWord.copyWith(
          word: en,
          translation: ko,
          sentence: _exController.text.trim(),
          reviewLevel: _level,
        ));
      } else {
        await repo.saveWord(Word(
          id: _generateId(),
          word: en,
          translation: ko,
          sentence: _exController.text.trim(),
          definition: '', // the edit sheet has no definition field (spec §5.4)
          platform: '',
          contentTitle: '',
          contentId: '',
          timestamp: 0,
          savedAt: DateTime.now().toIso8601String(),
          reviewLevel: _level,
        ));
      }
    } else {
      final existing = widget.item;
      if (existing != null) {
        final currentSentences = await repo.getSentences();
        Sentence? currentSentence;
        for (final s in currentSentences) {
          if (s.id == existing.id) {
            currentSentence = s;
            break;
          }
        }
        if (currentSentence == null) {
          widget.onSaved();
          if (mounted) Navigator.of(context).pop();
          return;
        }
        await repo.saveSentence(currentSentence.copyWith(
          original: en,
          translation: ko,
          reviewLevel: _level,
        ));
      } else {
        await repo.saveSentence(Sentence(
          id: _generateId(),
          original: en,
          translation: ko,
          platform: '',
          contentTitle: '',
          contentId: '',
          timestamp: 0,
          savedAt: DateTime.now().toIso8601String(),
          reviewLevel: _level,
        ));
      }
    }
    widget.onSaved();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final item = widget.item;
    if (item == null) return;
    final repo = context.read<LearningRepository>();
    if (item.isWord) {
      await repo.deleteWord(item.id);
    } else {
      await repo.deleteSentence(item.id);
    }
    widget.onSaved();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 18,
        bottom: 26 + MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFFFAFBFD),
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('취소')),
                Expanded(
                  child: Text(
                    _isNew ? '항목 추가' : '항목 수정',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ),
                TextButton(onPressed: _save, child: const Text('저장')),
              ],
            ),
            if (_isNew) ...[
              const SizedBox(height: 16),
              Container(
                key: const ValueKey('edit-type-toggle'),
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(color: const Color(0xFFE9ECF3), borderRadius: BorderRadius.circular(10)),
                child: Row(
                  children: [
                    Expanded(child: _typeSegment('단어', _isWord, () => setState(() => _isWord = true))),
                    Expanded(child: _typeSegment('문장', !_isWord, () => setState(() => _isWord = false))),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(_isWord ? '영어 단어' : '영어 원문', style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.inkQuaternary)),
            const SizedBox(height: 7),
            TextField(
              key: const ValueKey('edit-en-field'),
              controller: _enController,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            const Text('한글 뜻', style: TextStyle(fontFamily: AppFonts.mono, fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.inkQuaternary)),
            const SizedBox(height: 7),
            TextField(
              key: const ValueKey('edit-ko-field'),
              controller: _koController,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            if (_isWord) ...[
              const SizedBox(height: 16),
              const Text('응용 예문', style: TextStyle(fontFamily: AppFonts.mono, fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.inkQuaternary)),
              const SizedBox(height: 7),
              TextField(
                key: const ValueKey('edit-ex-field'),
                controller: _exController,
                maxLines: 3,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            ],
            const SizedBox(height: 18),
            const Text('복습 상태', style: TextStyle(fontFamily: AppFonts.mono, fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.inkQuaternary)),
            const SizedBox(height: 8),
            for (var lvl = 0; lvl <= kMaxReviewLevel; lvl++)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: _levelRow(lvl),
              ),
            if (!_isNew) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _delete,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    side: const BorderSide(color: AppColors.borderStrong),
                    foregroundColor: AppColors.danger,
                  ),
                  child: const Text('삭제'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _typeSegment(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 32,
        decoration: BoxDecoration(color: selected ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(8)),
        alignment: Alignment.center,
        child: Text(label, style: TextStyle(fontFamily: AppFonts.display, fontWeight: FontWeight.w600, fontSize: 12.5, color: selected ? AppColors.ink : AppColors.inkTertiary)),
      ),
    );
  }

  Widget _levelRow(int level) {
    final selected = _level == level;
    final days = kReviewIntervalDays[level];
    return GestureDetector(
      onTap: () => _pickLevel(level),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : Colors.white,
          border: Border.all(color: selected ? Colors.transparent : AppColors.borderStrong),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          children: [
            Text(kReviewLevelNames[level], style: const TextStyle(fontFamily: AppFonts.display, fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.ink)),
            const Spacer(),
            Text(days == null ? '-' : '$days일', style: TextStyle(fontFamily: AppFonts.mono, fontSize: 11.5, color: selected ? AppColors.ink : AppColors.inkQuaternary)),
          ],
        ),
      ),
    );
  }
}
