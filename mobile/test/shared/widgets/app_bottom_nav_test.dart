import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:english_helper_app/shared/widgets/app_bottom_nav.dart';

void main() {
  Widget buildNav(int selectedIndex, ValueChanged<int> onTap) {
    return MaterialApp(
      home: Scaffold(
        bottomNavigationBar: AppBottomNav(selectedIndex: selectedIndex, onTap: onTap),
      ),
    );
  }

  testWidgets('shows all 4 labels in the correct order', (tester) async {
    await tester.pumpWidget(buildNav(0, (_) {}));

    final labels = ['홈', '플래시카드', '타이머', '설정'];
    // 가져오기 탭은 클라우드 동기화가 대체했다(설계 §8·§9).
    expect(find.text('가져오기'), findsNothing);
    for (final label in labels) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('tapping an item calls onTap with its index', (tester) async {
    int? tapped;
    await tester.pumpWidget(buildNav(0, (i) => tapped = i));

    await tester.tap(find.text('타이머'));
    expect(tapped, 2);

    await tester.tap(find.text('설정'));
    expect(tapped, 3);
  });

  testWidgets('has no Material NavigationBar selection indicator', (tester) async {
    await tester.pumpWidget(buildNav(2, (_) {}));
    await tester.pump();

    // The mockup has no indicator pill behind the selected item at all —
    // confirms we aren't using the stock Material NavigationBar widget,
    // which always renders one.
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationIndicator), findsNothing);
  });
}
