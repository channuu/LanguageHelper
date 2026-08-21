import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/last_import_summary.dart';
import '../../data/repository.dart';
import '../../theme/app_theme.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  LastImportSummary? _lastImport;

  @override
  void initState() {
    super.initState();
    _loadLastImport();
  }

  Future<void> _loadLastImport() async {
    final repo = context.read<LearningRepository>();
    final summary = await repo.getLastImportSummary();
    if (!mounted) return;
    setState(() => _lastImport = summary);
  }

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
      await _loadLastImport();
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

  static String _dateTimeLabel(DateTime dt) {
    final period = dt.hour < 12 ? '오전' : '오후';
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    return '${dt.month}월 ${dt.day}일 $period $hour12:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final lastImport = _lastImport;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('가져오기', style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 8),
              const Text(
                '확장 프로그램 팝업에서 내보낸 .sqlite 파일을 선택하면 기존 데이터와 합칩니다. 같은 항목은 건너뜁니다.',
                style: TextStyle(fontSize: 13, height: 1.65, color: AppColors.inkTertiary),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () => _pickAndImport(context),
                child: Container(
                  height: 190,
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFD4DAE5)),
                    borderRadius: BorderRadius.circular(16),
                    color: AppColors.surface,
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFD4DAE5)),
                          color: AppColors.surface,
                        ),
                        alignment: Alignment.center,
                        child: const Icon(Icons.file_upload_outlined, size: 20, color: AppColors.inkSecondary),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'english_helper.sqlite',
                        style: TextStyle(fontFamily: AppFonts.mono, fontSize: 11, color: AppColors.inkQuaternary),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => _pickAndImport(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.ink,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                    '파일 선택',
                    style: TextStyle(fontFamily: AppFonts.display, fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ),
              ),
              if (lastImport != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'LAST IMPORT',
                        style: TextStyle(
                          fontFamily: AppFonts.mono,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.1,
                          color: AppColors.inkQuaternary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(_dateTimeLabel(lastImport.importedAt), style: const TextStyle(fontSize: 13.5)),
                          Text(
                            '+${lastImport.newWords + lastImport.newSentences}개',
                            style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 12, color: AppColors.accentInk),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '단어 ${lastImport.newWords} · 문장 ${lastImport.newSentences} 추가, '
                        '중복 ${lastImport.skippedWords + lastImport.skippedSentences}건 건너뜀',
                        style: const TextStyle(fontSize: 11.5, color: AppColors.inkQuaternary),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
