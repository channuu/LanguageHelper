import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/repository.dart';
import 'data/study_timer_repository.dart';
import 'data/sync/auth_service.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<LearningRepository>(
          create: (_) => LocalSQLiteRepository(),
        ),
        ChangeNotifierProvider<StudyTimerRepository>(
          create: (_) => LocalStudyTimerRepository(),
        ),
        Provider<AuthService>(create: (_) => FirebaseAuthService()),
      ],
      child: const EnglishHelperApp(),
    ),
  );
}
