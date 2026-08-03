import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:english_helper_app/shared/widgets/empty_state.dart';

void main() {
  testWidgets('renders the given message', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: EmptyState(message: '아직 저장된 항목이 없어요. Import 탭에서 불러오세요'),
      ),
    );

    expect(find.text('아직 저장된 항목이 없어요. Import 탭에서 불러오세요'), findsOneWidget);
  });
}
