import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';
import '../../shared/widgets/empty_state.dart';
import 'flashcard_item.dart';

class FlashcardScreen extends StatefulWidget {
  const FlashcardScreen({super.key});

  @override
  State<FlashcardScreen> createState() => _FlashcardScreenState();
}

class _FlashcardScreenState extends State<FlashcardScreen> {
  List<FlashcardItem>? _queue;
  bool _flipped = false;

  // Whether the review queue had any items at all when it was first loaded.
  // Used to distinguish "nothing saved yet" from "reviewed everything today".
  bool _hadItemsInitially = false;

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
    super.dispose();
  }

  // Reload automatically only when the user isn't mid-review (i.e. the
  // queue is currently empty, showing one of the empty states). This picks
  // up data that arrived via import (or was removed on the Home screen)
  // without yanking cards out from under an in-progress review session.
  void _onRepositoryChanged() {
    if (_queue == null || _queue!.isEmpty) {
      _loadQueue();
    }
  }

  Future<void> _loadQueue() async {
    final repo = context.read<LearningRepository>();
    final words = await repo.getWords();
    final sentences = await repo.getSentences();
    final items = [
      ...words.map(FlashcardItem.fromWord),
      ...sentences.map(FlashcardItem.fromSentence),
    ]..shuffle(Random());
    if (!mounted) return;
    setState(() {
      _queue = items;
      _hadItemsInitially = items.isNotEmpty;
    });
  }

  void _dontKnow() {
    setState(() {
      final current = _queue!.removeAt(0);
      _queue!.add(current);
      _flipped = false;
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
    });
  }

  @override
  Widget build(BuildContext context) {
    final queue = _queue;
    return Scaffold(
      appBar: AppBar(title: const Text('플래시카드')),
      body: Builder(builder: (context) {
        if (queue == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (queue.isEmpty) {
          return EmptyState(
            message: _hadItemsInitially
                ? '오늘 복습 완료! 🎉'
                : '아직 저장된 항목이 없어요.\n크롬 확장 프로그램에서 단어나 문장을 저장해보세요!',
          );
        }
        final current = queue.first;
        return Column(
          children: [
            Expanded(
              child: Center(
                child: GestureDetector(
                  onTap: () => setState(() => _flipped = !_flipped),
                  child: Card(
                    margin: const EdgeInsets.all(24),
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        _flipped ? current.back : current.front,
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: _dontKnow,
                    child: const Text('몰라요'),
                  ),
                  ElevatedButton(
                    onPressed: _know,
                    child: const Text('알아요'),
                  ),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }
}
