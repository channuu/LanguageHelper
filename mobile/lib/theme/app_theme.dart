import 'package:flutter/material.dart';

/// English Helper 디자인 토큰.
///
/// 값의 출처: Claude Design 목업 `English Helper UI.dc.html` §1a
/// ("자막은 어둡게, 학습은 밝게" 디자인 시스템). 앱 화면은 종이처럼 밝은
/// 표면을, Chrome 확장의 영상 위 UI는 어두운 표면을 쓴다 — 이 파일은
/// 앱(밝은 표면) 쪽 토큰만 다룬다.
///
/// oklch(0.74 0.16 45)/oklch(0.5 0.17 20)는 Dart `Color`가 지원하지 않아
/// sRGB hex로 변환한 값을 사용한다.
class AppColors {
  AppColors._();

  /// 목업의 모바일 아트보드는 모두 흰 배경이다. 카드는 흰 면 + border로
  /// 구분되므로 배경만 흰색으로 바꾼다.
  static const bg = Color(0xFFFFFFFF);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF14161F);
  static const inkSecondary = Color(0xFF454D5E);
  static const inkTertiary = Color(0xFF6F778A);
  static const inkQuaternary = Color(0xFF8D95A6);
  static const inkFaint = Color(0xFFACB3C2);
  static const border = Color(0xFFE7EAF1);
  static const borderStrong = Color(0xFFE1E5EE);

  /// oklch(0.74 0.16 45)
  static const accent = Color(0xFFFB864D);

  /// oklch(0.56 0.17 42) — 흰 배경 위 텍스트/링크용 진한 오렌지
  static const accentInk = Color(0xFFC24700);

  static const accentTint = Color(0x1AFB864D);

  /// oklch(0.5 0.17 20)
  static const danger = Color(0xFFAF2938);
}

/// 서체 역할. Schibsted Grotesk는 화면 제목·숫자·플래시카드 앞면,
/// IBM Plex Mono는 타임스탬프·개수·파일명에 쓴다 (design.md §1a).
class AppFonts {
  AppFonts._();

  static const display = 'Schibsted Grotesk';
  static const mono = 'IBM Plex Mono';
}

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: Brightness.light,
      primary: AppColors.accent,
      onPrimary: AppColors.ink,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      error: AppColors.danger,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.bg,
      fontFamily: AppFonts.display,
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontFamily: AppFonts.display,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.01,
          color: AppColors.ink,
        ),
        headlineLarge: TextStyle(
          fontFamily: AppFonts.display,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.01,
          color: AppColors.ink,
        ),
        headlineMedium: TextStyle(
          fontFamily: AppFonts.display,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.01,
          color: AppColors.ink,
        ),
        titleLarge: TextStyle(
          fontFamily: AppFonts.display,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
        titleMedium: TextStyle(
          fontFamily: AppFonts.display,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
        bodyLarge: TextStyle(fontFamily: AppFonts.display, color: AppColors.ink),
        bodyMedium: TextStyle(fontFamily: AppFonts.display, color: AppColors.inkSecondary),
        bodySmall: TextStyle(fontFamily: AppFonts.display, color: AppColors.inkTertiary),
        labelSmall: TextStyle(
          fontFamily: AppFonts.mono,
          letterSpacing: 0.1,
          color: AppColors.inkQuaternary,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.ink,
        elevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: AppFonts.display,
          fontWeight: FontWeight.w600,
          fontSize: 20,
          color: AppColors.ink,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.ink,
          textStyle: const TextStyle(fontFamily: AppFonts.display, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
