import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/repository.dart';
import 'data/study_timer_repository.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<LearningRepository>(
          create: (_) => LocalSQLiteRepository(),
        ),
        ChangeNotifierProvider<StudyTimerRepository>(
          create: (_) => LocalStudyTimerRepository(),
        ),
      ],
      child: const EnglishHelperApp(),
    ),
  );
}
