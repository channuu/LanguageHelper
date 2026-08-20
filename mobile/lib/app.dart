import 'package:flutter/material.dart';

import 'features/flashcard/flashcard_screen.dart';
import 'features/home/home_screen.dart';
import 'features/import/import_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/timer/timer_screen.dart';
import 'theme/app_theme.dart';

class EnglishHelperApp extends StatelessWidget {
  const EnglishHelperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'English Helper',
      theme: AppTheme.light,
      home: const _RootShell(),
    );
  }
}

class _RootShell extends StatefulWidget {
  const _RootShell();

  @override
  State<_RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<_RootShell> {
  int _index = 0;

  // Order matches the design mockup's AppNav.dc.html exactly:
  // 홈 / 플래시카드 / 타이머 / 가져오기 / 설정.
  static const _screens = [
    HomeScreen(),
    FlashcardScreen(),
    TimerScreen(),
    ImportScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: '홈'),
          NavigationDestination(icon: Icon(Icons.style), label: '플래시카드'),
          NavigationDestination(icon: Icon(Icons.timer), label: '타이머'),
          NavigationDestination(icon: Icon(Icons.file_download), label: '가져오기'),
          NavigationDestination(icon: Icon(Icons.settings), label: '설정'),
        ],
      ),
    );
  }
}
