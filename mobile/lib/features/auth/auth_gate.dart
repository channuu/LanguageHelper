import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/sync/auth_service.dart';
import '../../data/sync/sync_service.dart';
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
        final user = snapshot.data;
        if (user == null) {
          return LoginScreen(authService: authService);
        }
        // 계정 전환이면 이전 계정의 로컬 캐시를 비운다. 빌드 중에
        // 저장소를 건드리지 않도록 프레임 뒤로 미룬다.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          context.read<SyncService>().onSignedIn(user.uid);
        });
        return child;
      },
    );
  }
}
