import 'package:flutter/material.dart';

import '../../data/sync/auth_service.dart';
import 'login_screen.dart';

/// 인증 상태에 따라 로그인 화면과 앱 본체를 가른다.
/// 앱은 로그인이 필수다 — 미로그인 상태로는 아무것도 할 수 없다.
class AuthGate extends StatelessWidget {
  final AuthService authService;
  final Widget child;

  const AuthGate({super.key, required this.authService, required this.child});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthUser?>(
      stream: authService.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data == null) {
          return LoginScreen(authService: authService);
        }
        return child;
      },
    );
  }
}
