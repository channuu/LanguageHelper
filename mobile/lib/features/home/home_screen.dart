import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/sentence.dart';
import '../../data/models/word.dart';
import '../../data/repository.dart';
import '../../shared/widgets/empty_state.dart';
import 'detail_item.dart';
import 'item_detail_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('저장한 단어/문장'),
          bottom: const TabBar(
            tabs: [Tab(text: '단어'), Tab(text: '문장')],
          ),
        ),
        body: const TabBarView(
          children: [_WordList(), _SentenceList()],
        ),
      ),
    );
  }
}

class _WordList extends StatelessWidget {
  const _WordList();

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<LearningRepository>();
    return FutureBuilder<List<Word>>(
      future: repo.getWords(),
      builder: (context, snapshot) {
        final words = snapshot.data ?? const [];
        if (snapshot.connectionState == ConnectionState.done && words.isEmpty) {
          return const EmptyState(
            message: '아직 저장된 항목이 없어요. Import 탭에서 불러오세요',
          );
        }
        return ListView.builder(
          itemCount: words.length,
          itemBuilder: (context, index) {
            final word = words[index];
            return Dismissible(
              key: ValueKey(word.id),
              direction: DismissDirection.endToStart,
              background: Container(color: Colors.red),
              onDismissed: (_) => repo.deleteWord(word.id),
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
            );
          },
        );
      },
    );
  }
}

class _SentenceList extends StatelessWidget {
  const _SentenceList();

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<LearningRepository>();
    return FutureBuilder<List<Sentence>>(
      future: repo.getSentences(),
      builder: (context, snapshot) {
        final sentences = snapshot.data ?? const [];
        if (snapshot.connectionState == ConnectionState.done && sentences.isEmpty) {
          return const EmptyState(
            message: '아직 저장된 항목이 없어요. Import 탭에서 불러오세요',
          );
        }
        return ListView.builder(
          itemCount: sentences.length,
          itemBuilder: (context, index) {
            final sentence = sentences[index];
            return Dismissible(
              key: ValueKey(sentence.id),
              direction: DismissDirection.endToStart,
              background: Container(color: Colors.red),
              onDismissed: (_) => repo.deleteSentence(sentence.id),
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
            );
          },
        );
      },
    );
  }
}
