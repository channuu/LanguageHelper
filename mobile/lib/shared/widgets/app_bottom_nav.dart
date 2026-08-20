import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Bottom navigation bar matching `AppNav.dc.html` exactly: custom
/// hand-drawn stroke icons, no selection indicator/pill (the mockup only
/// changes icon/label color between active and inactive), and the mockup's
/// precise sizing/colors.
class AppBottomNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const AppBottomNav({super.key, required this.selectedIndex, required this.onTap});

  static const _labels = ['홈', '플래시카드', '타이머', '가져오기', '설정'];

  /// oklch(0.58 0.17 42) — the mockup's active nav color (distinct from
  /// AppColors.accentInk, which is oklch(0.56 0.17 42)).
  static const _active = Color(0xFFC94E0C);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 88,
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 26),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < 5; i++)
            Expanded(
              child: _NavItem(
                index: i,
                label: _labels[i],
                selected: i == selectedIndex,
                onTap: () => onTap(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final int index;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({required this.index, required this.label, required this.selected, required this.onTap});

  static CustomPainter _painterFor(int index, Color color) {
    switch (index) {
      case 0:
        return _HomeIconPainter(color);
      case 1:
        return _FlashcardIconPainter(color);
      case 2:
        return _TimerIconPainter(color);
      case 3:
        return _ImportIconPainter(color);
      default:
        return _SettingsIconPainter(color);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppBottomNav._active : AppColors.inkQuaternary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 21, height: 21, child: CustomPaint(painter: _painterFor(index, color))),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(fontFamily: AppFonts.display, fontSize: 10.5, letterSpacing: 0.21, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

Paint _strokePaint(Color color, {double width = 1.5}) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

class _HomeIconPainter extends CustomPainter {
  final Color color;
  const _HomeIconPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(3, 9.4)
      ..lineTo(10.5, 3.4)
      ..lineTo(18, 9.4)
      ..lineTo(18, 17)
      ..arcToPoint(const Offset(17, 18), radius: const Radius.circular(1))
      ..lineTo(14.4, 18)
      ..lineTo(14.4, 12.8)
      ..lineTo(8.1, 12.8)
      ..lineTo(8.1, 18)
      ..lineTo(4, 18)
      ..arcToPoint(const Offset(3, 17), radius: const Radius.circular(1))
      ..close();
    canvas.drawPath(path, _strokePaint(color, width: 1.5)..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(covariant _HomeIconPainter oldDelegate) => oldDelegate.color != color;
}

class _FlashcardIconPainter extends CustomPainter {
  final Color color;
  const _FlashcardIconPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = _strokePaint(color);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(5.4, 3.6, 12, 9), const Radius.circular(1.6)),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(3.4, 8.4, 12, 9), const Radius.circular(1.6)),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _FlashcardIconPainter oldDelegate) => oldDelegate.color != color;
}

class _TimerIconPainter extends CustomPainter {
  final Color color;
  const _TimerIconPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = _strokePaint(color);
    canvas.drawCircle(const Offset(10.5, 11.4), 7, paint);
    final hand = Path()
      ..moveTo(10.5, 7.6)
      ..lineTo(10.5, 11.4)
      ..lineTo(13.1, 13.2);
    canvas.drawPath(hand, paint);
    canvas.drawLine(const Offset(8.2, 2.6), const Offset(12.8, 2.6), paint);
  }

  @override
  bool shouldRepaint(covariant _TimerIconPainter oldDelegate) => oldDelegate.color != color;
}

class _ImportIconPainter extends CustomPainter {
  final Color color;
  const _ImportIconPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = _strokePaint(color);
    final arrow = Path()
      ..moveTo(10.5, 3.2)
      ..lineTo(10.5, 11.8)
      ..moveTo(10.5, 11.8)
      ..lineTo(7.4, 8.7)
      ..moveTo(10.5, 11.8)
      ..lineTo(13.6, 8.7);
    canvas.drawPath(arrow, paint);
    final tray = Path()
      ..moveTo(3.6, 13.4)
      ..lineTo(3.6, 15.8)
      ..arcToPoint(const Offset(5.4, 17.6), radius: const Radius.circular(1.8))
      ..lineTo(15.6, 17.6)
      ..arcToPoint(const Offset(17.4, 15.8), radius: const Radius.circular(1.8))
      ..lineTo(17.4, 13.4);
    canvas.drawPath(tray, paint);
  }

  @override
  bool shouldRepaint(covariant _ImportIconPainter oldDelegate) => oldDelegate.color != color;
}

class _SettingsIconPainter extends CustomPainter {
  final Color color;
  const _SettingsIconPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = _strokePaint(color);
    canvas.drawLine(const Offset(3.4, 7.2), const Offset(17.6, 7.2), linePaint);
    canvas.drawLine(const Offset(3.4, 13.8), const Offset(17.6, 13.8), linePaint);

    final knobFill = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    for (final center in const [Offset(8, 7.2), Offset(13.4, 13.8)]) {
      canvas.drawCircle(center, 2.1, knobFill);
      canvas.drawCircle(center, 2.1, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SettingsIconPainter oldDelegate) => oldDelegate.color != color;
}
