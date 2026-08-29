import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:english_helper_app/data/sync/auth_service.dart';
import 'package:english_helper_app/features/auth/login_screen.dart';

class FakeAuthService implements AuthService {
  String? signedInEmail;
  String? signedUpEmail;
  Object? throwOnSignIn;

  @override
  AuthUser? currentUser;

  @override
  Stream<AuthUser?> authStateChanges() => Stream.value(currentUser);

  @override
  Future<void> signIn(String email, String password) async {
    if (throwOnSignIn != null) throw throwOnSignIn!;
    signedInEmail = email;
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
}
