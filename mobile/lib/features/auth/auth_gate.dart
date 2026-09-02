import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/sync/auth_service.dart';
import '../../data/sync/sync_service.dart';
import 'login_screen.dart';

/// 인증 상태에 따라 로그인 화면과 앱 본체를 가른다.
/// 앱은 로그인이 필수다 — 미로그인 상태로는 아무것도 할 수 없다.
class AuthGate extends StatefulWidget {
  final AuthService authService;
  final Widget child;

  const AuthGate({super.key, required this.authService, required this.child});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  /// 계정 전환 검사를 태운 uid. 스트림은 같은 사용자를 여러 번 흘릴 수 있고
  /// onSignedIn은 syncNow까지 부르므로, 실제로 계정이 바뀐 순간에만 부른다.
  String? _checkedUid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthUser?>(
      stream: widget.authService.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snapshot.data;
        if (user == null) {
          _checkedUid = null;
          return LoginScreen(authService: widget.authService);
        }
        if (_checkedUid != user.uid) {
          _checkedUid = user.uid;
          // 계정 전환이면 이전 계정의 로컬 캐시를 비운다. 빌드 중에 저장소를
          // 건드리지 않도록 프레임 뒤로 미루고, 콜백이 도는 사이 위젯이
          // 사라져도 죽은 context를 읽지 않도록 지금 캡처해 둔다.
          final sync = context.read<SyncService>();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            sync.onSignedIn(user.uid);
          });
        }
        return widget.child;
      },
    );
  }
}
