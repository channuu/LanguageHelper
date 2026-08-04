import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/repository.dart';

const Map<String, String> kNativeLanguages = {
  'ko': '한국어',
  'ja': '日本語',
  'zh': '中文',
  'es': 'Español',
  'fr': 'Français',
  'de': 'Deutsch',
};

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _nativeLang = 'ko';
  String? _dbPath;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final dbPath = await context.read<LearningRepository>().getDatabasePath();
    if (!mounted) return;
    setState(() {
      _nativeLang = prefs.getString('native_lang') ?? 'ko';
      _dbPath = dbPath;
    });
  }

  Future<void> _setNativeLang(String lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('native_lang', lang);
    if (!mounted) return;
    setState(() => _nativeLang = lang);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('모국어 (Native Language)'),
            trailing: DropdownButton<String>(
              value: _nativeLang,
              items: kNativeLanguages.entries
                  .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (value) {
                if (value != null) _setNativeLang(value);
              },
            ),
          ),
          ListTile(
            title: const Text('DB 파일 경로'),
            subtitle: Text(_dbPath ?? '불러오는 중...'),
          ),
        ],
      ),
    );
  }
}
