import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/repository.dart';

void main() {
  runApp(
    ChangeNotifierProvider<LearningRepository>(
      create: (_) => LocalSQLiteRepository(),
      child: const EnglishHelperApp(),
    ),
  );
}
