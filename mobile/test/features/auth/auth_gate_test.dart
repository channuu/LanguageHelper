// 인증 상태가 아직 오지 않았을 때 로그인 화면을 먼저 그리면, 이미
// 로그인한 사용자도 앱을 열 때마다 로그인 화면이 번쩍인다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:english_helper_app/data/sync/auth_service.dart';
import 'package:english_helper_app/features/auth/auth_gate.dart';

class _PendingAuthService implements AuthService {
  final _controller = StreamController<AuthUser?>();

  @override
  AuthUser? currentUser;

  @override
  Stream<AuthUser?> authStateChanges() => _controller.stream;

  void emit(AuthUser? user) {
    currentUser = user;
    _controller.add(user);
  }

  @override
  Future<void> signIn(String email, String password) async {}
  @override
  Future<void> signUp(String email, String password) async {}
  @override
  Future<void> signOut() async {}
}

void main() {
  testWidgets('인증 상태를 기다리는 동안 로그인 화면을 그리지 않는다',
      (tester) async {
    final auth = _PendingAuthService();

    await tester.pumpWidget(MaterialApp(
      home: AuthGate(
        authService: auth,
        child: const Scaffold(body: Text('본체')),
      ),
    ));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('로그인'), findsNothing);
    expect(find.text('본체'), findsNothing);
  });

  testWidgets('미로그인이 확정되면 로그인 화면을 그린다', (tester) async {
    final auth = _PendingAuthService();

    await tester.pumpWidget(MaterialApp(
      home: AuthGate(
        authService: auth,
        child: const Scaffold(body: Text('본체')),
      ),
    ));
    auth.emit(null);
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('본체'), findsNothing);
    expect(find.text('로그인'), findsWidgets);
  });
}
