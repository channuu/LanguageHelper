import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:english_helper_app/data/sync/auth_service.dart';
import 'package:english_helper_app/features/auth/login_screen.dart';
import 'package:english_helper_app/theme/app_theme.dart';

class FakeAuthService implements AuthService {
  String? signedInEmail;
  String? signedUpEmail;
  Object? throwOnSignIn;

  @override
  AuthUser? currentUser;

  @override
  Stream<AuthUser?> authStateChanges() => Stream.value(currentUser);

  /// 완료되지 않는 로그인을 흉내 내 진행 중 상태를 검사할 때 쓴다.
  Completer<void>? pendingSignIn;

  @override
  Future<void> signIn(String email, String password) async {
    if (throwOnSignIn != null) throw throwOnSignIn!;
    signedInEmail = email;
    if (pendingSignIn != null) await pendingSignIn!.future;
  }

  @override
  Future<void> signUp(String email, String password) async {
    signedUpEmail = email;
  }

  @override
  Future<void> signOut() async {
    currentUser = null;
  }
}

Future<void> pumpLogin(WidgetTester tester, AuthService auth) {
  return tester.pumpWidget(
    MaterialApp(home: LoginScreen(authService: auth)),
  );
}

void main() {
  testWidgets('이메일과 비밀번호를 넣고 로그인하면 authService를 호출한다', (tester) async {
    final auth = FakeAuthService();
    await pumpLogin(tester, auth);

    await tester.enterText(find.byKey(const Key('login-email')), 'a@b.c');
    await tester.enterText(find.byKey(const Key('login-password')), 'pw123456');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(auth.signedInEmail, 'a@b.c');
  });

  testWidgets('빈 입력이면 호출하지 않고 안내를 띄운다', (tester) async {
    final auth = FakeAuthService();
    await pumpLogin(tester, auth);

    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(auth.signedInEmail, isNull);
    expect(find.text('이메일과 비밀번호를 입력해 주세요'), findsOneWidget);
  });

  testWidgets('회원가입 탭에서 6자 미만 비밀번호는 막는다', (tester) async {
    final auth = FakeAuthService();
    await pumpLogin(tester, auth);

    await tester.tap(find.text('회원가입'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('login-email')), 'a@b.c');
    await tester.enterText(find.byKey(const Key('login-password')), 'pw12');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(auth.signedUpEmail, isNull);
    expect(find.text('비밀번호는 6자 이상이어야 해요'), findsOneWidget);
  });

  testWidgets('인증 실패 메시지를 화면에 보여준다', (tester) async {
    final auth = FakeAuthService()
      ..throwOnSignIn = AuthException('이메일 또는 비밀번호가 맞지 않아요');
    await pumpLogin(tester, auth);

    await tester.enterText(find.byKey(const Key('login-email')), 'a@b.c');
    await tester.enterText(find.byKey(const Key('login-password')), 'wrongpw');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(find.text('이메일 또는 비밀번호가 맞지 않아요'), findsOneWidget);
  });

  test('에러 코드를 확장과 같은 문구로 옮긴다', () {
    expect(authErrorMessage('email-already-in-use'), '이미 가입된 이메일이에요');
    expect(authErrorMessage('wrong-password'), '이메일 또는 비밀번호가 맞지 않아요');
    expect(authErrorMessage('user-not-found'), '이메일 또는 비밀번호가 맞지 않아요');
    expect(authErrorMessage('invalid-credential'), '이메일 또는 비밀번호가 맞지 않아요');
    expect(authErrorMessage('weak-password'), '비밀번호는 6자 이상이어야 해요');
    expect(authErrorMessage('too-many-requests'), '잠시 후 다시 시도해 주세요');
    expect(authErrorMessage('network-request-failed'), '연결을 확인해 주세요');
    expect(authErrorMessage('something-else'), '로그인에 실패했어요');
  });

  // 아래는 목업(English Helper UI.dc.html, artboard 2a)에 맞춘 화면 구성이다.
  testWidgets('로그인 모드에서 목업의 제목과 안내를 보여준다', (tester) async {
    await pumpLogin(tester, FakeAuthService());

    expect(find.text('다시 이어서\n복습할까요'), findsOneWidget);
    expect(find.text('저장한 단어를 모든 기기에서 보려면 로그인하세요.'), findsOneWidget);
  });

  testWidgets('회원가입 탭으로 바꾸면 제목과 안내가 함께 바뀐다', (tester) async {
    await pumpLogin(tester, FakeAuthService());

    await tester.tap(find.text('회원가입'));
    await tester.pumpAndSettle();

    expect(find.text('단어를 모으는\n계정을 만들어요'), findsOneWidget);
    expect(
        find.text('이메일만 있으면 됩니다. 브라우저에서 저장한 단어가 바로 이어집니다.'),
        findsOneWidget);
  });

  testWidgets('입력란에 목업의 라벨과 힌트를 쓴다', (tester) async {
    await pumpLogin(tester, FakeAuthService());

    expect(find.text('EMAIL'), findsOneWidget);
    expect(find.text('PASSWORD'), findsOneWidget);
    expect(find.text('you@example.com'), findsOneWidget);
    expect(find.text('비밀번호'), findsOneWidget);

    await tester.tap(find.text('회원가입'));
    await tester.pumpAndSettle();

    expect(find.text('6자 이상'), findsOneWidget,
        reason: '회원가입에서는 비밀번호 힌트가 규칙을 알려준다');
  });

  testWidgets('로그인이 진행 중이면 버튼이 연결 중으로 바뀐다', (tester) async {
    final auth = FakeAuthService()..pendingSignIn = Completer<void>();
    await pumpLogin(tester, auth);

    await tester.enterText(find.byKey(const Key('login-email')), 'a@b.c');
    await tester.enterText(find.byKey(const Key('login-password')), 'pw123456');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pump();

    expect(find.text('연결 중…'), findsOneWidget);

    auth.pendingSignIn!.complete();
    await tester.pumpAndSettle();
  });

  test('앱 배경은 흰색이다', () {
    // 목업의 모든 모바일 아트보드가 #ffffff로 바뀌었다.
    expect(AppTheme.light.scaffoldBackgroundColor, const Color(0xFFFFFFFF));
  });
}
