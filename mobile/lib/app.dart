import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/sync/auth_service.dart';
import 'data/sync/sync_service.dart';
import 'features/auth/auth_gate.dart';
import 'features/flashcard/flashcard_screen.dart';
import 'features/home/home_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/timer/timer_screen.dart';
import 'shared/widgets/app_bottom_nav.dart';
import 'theme/app_theme.dart';

class EnglishHelperApp extends StatelessWidget {
  const EnglishHelperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'English Helper',
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => AuthGate(
          authService: context.read<AuthService>(),
          child: const _RootShell(),
        ),
      ),
    );
  }
}

class _RootShell extends StatefulWidget {
  const _RootShell();

  @override
  State<_RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<_RootShell> with WidgetsBindingObserver {
  int _index = 0;

  // Order matches the design mockup's AppNav.dc.html exactly:
  // 홈 / 플래시카드 / 타이머 / 설정.
  static const _screens = [
    HomeScreen(),
    FlashcardScreen(),
    TimerScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _sync();
  }

  /// 앱 진입과 포그라운드 복귀에서만 부른다 — 다른 기기가 올린 변경을
  /// 사용자가 화면을 다시 볼 때 받아온다.
  void _sync() {
    if (!mounted) return;
    final uid = context.read<AuthService>().currentUser?.uid;
    if (uid == null) return;
    context.read<SyncService>().syncNow(uid);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: AppBottomNav(
        selectedIndex: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}
