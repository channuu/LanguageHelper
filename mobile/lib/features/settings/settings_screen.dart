import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/repository.dart';
import '../../data/study_timer_repository.dart';
import '../../data/sync/auth_service.dart';
import '../../data/sync/sync_service.dart';
import '../../theme/app_theme.dart';
import '../timer/weekly_goal_card.dart';

const Map<String, String> kNativeLanguages = {
  'ko': '한국어',
  'ja': '日本語',
  'zh': '中文',
  'es': 'Español',
  'fr': 'Français',
  'de': 'Deutsch',
};

const Map<String, String> kFlashcardFrontOptions = {
  'en': '영어',
  'ko': '한글',
};

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _nativeLang = 'ko';
  int _dailyReviewGoal = 20;
  String _flashcardFront = 'en';
  bool _showSourceSentence = true;
  String? _dbPath;
  int? _savedItemCount;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = context.read<LearningRepository>();
    final prefs = await SharedPreferences.getInstance();
    final dbPath = await repo.getDatabasePath();
    final words = await repo.getWords();
    final sentences = await repo.getSentences();
    if (!mounted) return;
    setState(() {
      _nativeLang = prefs.getString('native_lang') ?? 'ko';
      _dailyReviewGoal = prefs.getInt('daily_review_goal') ?? 20;
      _flashcardFront = prefs.getString('flashcard_front') ?? 'en';
      _showSourceSentence = prefs.getBool('show_source_sentence') ?? true;
      _dbPath = dbPath;
      _savedItemCount = words.length + sentences.length;
    });
  }

  Future<void> _setNativeLang(String lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('native_lang', lang);
    if (!mounted) return;
    setState(() => _nativeLang = lang);
  }

  Future<void> _setFlashcardFront(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('flashcard_front', value);
    if (!mounted) return;
    setState(() => _flashcardFront = value);
  }

  Future<void> _setShowSourceSentence(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_source_sentence', value);
    if (!mounted) return;
    setState(() => _showSourceSentence = value);
  }

  Future<void> _editDailyReviewGoal(BuildContext context) async {
    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DailyGoalSheet(initialValue: _dailyReviewGoal),
    );
    if (result == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('daily_review_goal', result);
    if (!mounted) return;
    setState(() => _dailyReviewGoal = result);
  }

  Future<void> _editNativeLang(BuildContext context) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChoiceSheet(
        title: '모국어',
        options: kNativeLanguages,
        selected: _nativeLang,
      ),
    );
    if (result != null) await _setNativeLang(result);
  }

  Future<void> _editFlashcardFront(BuildContext context) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChoiceSheet(
        title: '앞면에 표시',
        options: kFlashcardFrontOptions,
        selected: _flashcardFront,
      ),
    );
    if (result != null) await _setFlashcardFront(result);
  }

  Future<void> _editWeeklyGoal(BuildContext context, StudyTimerRepository timerRepo) async {
    final weekStart = mondayOf(DateTime.now());
    final goalMinutes = await timerRepo.getWeeklyGoalMinutes(weekStart);
    final sessions = await timerRepo.getSessionsBetween(weekStart, weekStart.add(const Duration(days: 7)));
    final totalSeconds = sessions.fold<int>(0, (sum, s) => sum + s.durationSeconds);

    if (!context.mounted) return;
    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GoalSheet(
        initialHours: (goalMinutes ?? 300) ~/ 60,
        currentTotalSeconds: totalSeconds,
      ),
    );
    if (result != null) {
      await timerRepo.setWeeklyGoal(result * 60);
      if (mounted) setState(() {}); // refresh the displayed "{H}시간" row
    }
  }

  Future<void> _confirmSignOut(
      BuildContext context, AuthService auth, SyncService sync) async {
    final uid = auth.currentUser?.uid;
    if (uid == null) return;

    // 로그아웃은 로컬 캐시를 비운다 — 강제(force) 없이 먼저 시도해서,
    // 아직 서버에 닿지 않은 항목이 있으면 signOut이 거부하게 둔다.
    var result = await sync.signOut(uid);
    if (!result.ok) {
      if (!context.mounted) return;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(
            '${result.pending}개 항목이 아직 저장되지 않았어요. '
            '로그아웃하면 사라집니다. 계속할까요?',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('취소')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('로그아웃')),
          ],
        ),
      );
      if (proceed != true) return;
      result = await sync.signOut(uid, force: true);
    }
    // sync.signOut까지 끝난 뒤에 auth.signOut을 불러야 한다 — 순서가
    // 바뀌면 인증 상태 스트림이 먼저 화면을 걷어내 위 로컬 정리가
    // 끝나기 전에 위젯이 dispose된다.
    await auth.signOut();
  }

  static String _formatSyncTime(String? iso) {
    if (iso == null) return '아직 동기화 안 됨';
    final d = DateTime.parse(iso);
    return '${d.hour}:${d.minute.toString().padLeft(2, '0')} 동기화됨';
  }

  Widget _accountSection(BuildContext context) {
    final auth = context.watch<AuthService>();
    final sync = context.watch<SyncService>();
    final email = auth.currentUser?.email ?? '';

    return _SettingsCard(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(email, style: const TextStyle(fontSize: 14)),
                  ),
                  Text(
                    sync.pending > 0
                        ? '${sync.pending}개 대기 중'
                        : _formatSyncTime(sync.lastSyncAt),
                    style: TextStyle(
                      fontSize: 13,
                      color: sync.pending > 0
                          ? AppColors.accent
                          : AppColors.inkTertiary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(
                    onPressed: () {
                      final uid = auth.currentUser?.uid;
                      if (uid != null) sync.syncNow(uid);
                    },
                    child: const Text('지금 동기화'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => _confirmSignOut(context, auth, sync),
                    child: const Text('로그아웃'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final timerRepo = context.watch<StudyTimerRepository>();

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('설정', style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 20),
            _SectionLabel('계정'),
            _accountSection(context),
            const SizedBox(height: 22),
            _SectionLabel('학습'),
            _SettingsCard(
              children: [
                _ChevronRow(
                  label: '모국어',
                  value: kNativeLanguages[_nativeLang] ?? _nativeLang,
                  onTap: () => _editNativeLang(context),
                ),
                _ChevronRow(
                  label: '하루 복습 목표',
                  value: '$_dailyReviewGoal개',
                  onTap: () => _editDailyReviewGoal(context),
                ),
                _ChevronRow(
                  label: '주간 학습 목표',
                  value: FutureBuilder<int?>(
                    future: timerRepo.getWeeklyGoalMinutes(mondayOf(DateTime.now())),
                    builder: (context, snapshot) {
                      final minutes = snapshot.data ?? 300;
                      return Text('${minutes ~/ 60}시간', style: const TextStyle(fontSize: 14, color: AppColors.inkTertiary));
                    },
                  ),
                  onTap: () => _editWeeklyGoal(context, timerRepo),
                  isLast: true,
                ),
              ],
            ),
            const SizedBox(height: 22),
            _SectionLabel('플래시카드'),
            _SettingsCard(
              children: [
                _ChevronRow(
                  label: '앞면에 표시',
                  value: kFlashcardFrontOptions[_flashcardFront] ?? _flashcardFront,
                  onTap: () => _editFlashcardFront(context),
                ),
                _SwitchRow(
                  label: '출처 문장 함께 보기',
                  value: _showSourceSentence,
                  onChanged: _setShowSourceSentence,
                  isLast: true,
                ),
              ],
            ),
            const SizedBox(height: 22),
            _SectionLabel('데이터'),
            _SettingsCard(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('DB 파일 경로', style: TextStyle(fontSize: 14)),
                      const SizedBox(height: 5),
                      Text(
                        _dbPath ?? '불러오는 중...',
                        style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 11.5, color: AppColors.inkQuaternary),
                      ),
                    ],
                  ),
                ),
                Container(height: 1, color: const Color(0xFFF1F3F8)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                  child: Row(
                    children: [
                      const Expanded(child: Text('저장된 항목', style: TextStyle(fontSize: 14))),
                      Text(
                        '${_savedItemCount ?? 0}',
                        style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 13, color: AppColors.inkTertiary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'English Helper 0.4.0 · Phase B',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: AppFonts.mono,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
          color: AppColors.inkQuaternary,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _ChevronRow extends StatelessWidget {
  final String label;
  final Object value; // String or a Widget (e.g. FutureBuilder)
  final VoidCallback onTap;
  final bool isLast;
  const _ChevronRow({required this.label, required this.value, required this.onTap, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    final valueWidget = value is Widget
        ? value as Widget
        : Text('$value', style: const TextStyle(fontSize: 14, color: AppColors.inkTertiary));
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: isLast
            ? null
            : const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF1F3F8)))),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
            valueWidget,
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, size: 16, color: AppColors.inkFaint),
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool isLast;
  const _SwitchRow({required this.label, required this.value, required this.onChanged, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: isLast
          ? null
          : const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF1F3F8)))),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          Switch(value: value, onChanged: onChanged, activeThumbColor: AppColors.accent),
        ],
      ),
    );
  }
}

class _ChoiceSheet extends StatelessWidget {
  final String title;
  final Map<String, String> options;
  final String selected;
  const _ChoiceSheet({required this.title, required this.options, required this.selected});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: Color(0xFFFAFBFD),
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: const Color(0xFFDCE1EA), borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Text(title, style: const TextStyle(fontFamily: AppFonts.display, fontWeight: FontWeight.w600, fontSize: 20)),
          const SizedBox(height: 14),
          for (final entry in options.entries)
            GestureDetector(
              onTap: () => Navigator.of(context).pop(entry.key),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF1F3F8)))),
                child: Row(
                  children: [
                    Expanded(child: Text(entry.value, style: const TextStyle(fontSize: 15))),
                    if (entry.key == selected) const Icon(Icons.check, size: 18, color: AppColors.accentInk),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DailyGoalSheet extends StatefulWidget {
  final int initialValue;
  const _DailyGoalSheet({required this.initialValue});

  @override
  State<_DailyGoalSheet> createState() => _DailyGoalSheetState();
}

class _DailyGoalSheetState extends State<_DailyGoalSheet> {
  late int _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.initialValue;
  }

  void _adjust(int delta) => setState(() => _draft = (_draft + delta).clamp(1, 999));

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: Color(0xFFFAFBFD),
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: const Color(0xFFDCE1EA), borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const Text('하루 복습 목표', style: TextStyle(fontFamily: AppFonts.display, fontWeight: FontWeight.w600, fontSize: 20)),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () => _adjust(-1),
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(border: Border.all(color: const Color(0xFFDCE1EA)), borderRadius: BorderRadius.circular(14)),
                  alignment: Alignment.center,
                  child: const Text('−', style: TextStyle(fontSize: 22, color: AppColors.inkSecondary)),
                ),
              ),
              SizedBox(
                width: 100,
                child: Text('$_draft개', textAlign: TextAlign.center, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w600)),
              ),
              GestureDetector(
                onTap: () => _adjust(1),
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(border: Border.all(color: const Color(0xFFDCE1EA)), borderRadius: BorderRadius.circular(14)),
                  alignment: Alignment.center,
                  child: const Text('+', style: TextStyle(fontSize: 22, color: AppColors.inkSecondary)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(_draft),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.ink,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('저장', style: TextStyle(fontFamily: AppFonts.display, fontWeight: FontWeight.w600, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}
