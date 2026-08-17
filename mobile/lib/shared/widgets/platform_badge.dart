import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class _BadgeStyle {
  final String label;
  final Color bg;
  final Color fg;
  const _BadgeStyle({required this.label, required this.bg, required this.fg});
}

/// Small colored pill showing a source platform (YouTube/Netflix/etc).
///
/// This is the one UI element allowed a non-grayscale color under the
/// design system's "ink scale everywhere except platform badges" rule
/// (mockup §1a).
class PlatformBadge extends StatelessWidget {
  final String platform;

  const PlatformBadge({super.key, required this.platform});

  static const Map<String, _BadgeStyle> _styles = {
    'youtube': _BadgeStyle(label: 'YouTube', bg: Color(0x1AFF0000), fg: Color(0xFFCC0000)),
    'netflix': _BadgeStyle(label: 'Netflix', bg: Color(0x1AE50914), fg: Color(0xFFB0060F)),
    'disney': _BadgeStyle(label: 'Disney+', bg: Color(0x1A0063E5), fg: Color(0xFF0050B8)),
    'coupang': _BadgeStyle(label: '쿠팡플레이', bg: Color(0x1A00C73C), fg: Color(0xFF00A030)),
  };

  @override
  Widget build(BuildContext context) {
    final style = _styles[platform.toLowerCase()] ??
        _BadgeStyle(label: platform, bg: const Color(0x14454D5E), fg: AppColors.inkTertiary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(color: style.bg, borderRadius: BorderRadius.circular(4)),
      child: Text(
        style.label,
        style: TextStyle(
          fontFamily: AppFonts.mono,
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.06,
          color: style.fg,
        ),
      ),
    );
  }
}
