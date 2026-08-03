import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';

class ImportScreen extends StatelessWidget {
  const ImportScreen({super.key});

  Future<void> _pickAndImport(BuildContext context) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['sqlite'],
    );
    if (result == null || result.files.single.path == null) return;

    if (!context.mounted) return;
    final repo = context.read<LearningRepository>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      final merged = await repo.mergeFromFile(result.files.single.path!);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '단어 ${merged.newWords}개, 문장 ${merged.newSentences}개를 가져왔습니다',
          ),
        ),
      );
    } on InvalidBackupFileException catch (e) {
      if (!context.mounted) return;
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('가져오기 실패'),
          content: Text(e.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('확인'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('가져오기')),
      body: Center(
        child: ElevatedButton.icon(
          icon: const Icon(Icons.file_open),
          label: const Text('SQLite 파일 선택'),
          onPressed: () => _pickAndImport(context),
        ),
      ),
    );
  }
}
