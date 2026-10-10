import 'package:firebase_auth/firebase_auth.dart' as fb;

class AuthUser {
  final String uid;
  final String email;
  const AuthUser({required this.uid, required this.email});
}

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);
  @override
  String toString() => message;
}

const Map<String, String> _errorCopy = {
  'email-already-in-use': '이미 가입된 이메일이에요',
  'user-not-found': '이메일 또는 비밀번호가 맞지 않아요',
  'wrong-password': '이메일 또는 비밀번호가 맞지 않아요',
  'invalid-credential': '이메일 또는 비밀번호가 맞지 않아요',
  'invalid-email': '이메일 형식을 확인해 주세요',
  'weak-password': '비밀번호는 6자 이상이어야 해요',
  'too-many-requests': '잠시 후 다시 시도해 주세요',
  'user-disabled': '사용할 수 없는 계정이에요',
  'network-request-failed': '연결을 확인해 주세요',
  'requires-recent-login': '보안을 위해 비밀번호를 다시 입력해 주세요',
};

/// 확장의 cloud/auth.js와 같은 문구를 쓴다. 어느 쪽이 틀렸는지
/// (이메일/비밀번호) 구분해 알려주지 않는다.
String authErrorMessage(String code) =>
    _errorCopy[code] ?? '로그인에 실패했어요';

abstract class AuthService {
  Stream<AuthUser?> authStateChanges();
  AuthUser? get currentUser;
  Future<void> signIn(String email, String password);
  Future<void> signUp(String email, String password);
  Future<void> signOut();

  /// 계정과 인증 정보를 영구히 삭제한다. Firebase는 최근 로그인하지 않은
  /// 사용자의 삭제를 거부하므로 비밀번호로 먼저 재인증한다.
  ///
  /// 호출 전에 Firestore 문서를 먼저 지워야 한다 — 규칙이
  /// request.auth.uid == uid라, 계정이 사라지면 그 데이터를 지울 권한도
  /// 함께 사라져 영구히 고아로 남는다.
  Future<void> deleteAccount(String password);
}

class FirebaseAuthService implements AuthService {
  final fb.FirebaseAuth _auth;

  FirebaseAuthService({fb.FirebaseAuth? auth})
      : _auth = auth ?? fb.FirebaseAuth.instance;

  static AuthUser? _toUser(fb.User? user) => user == null
      ? null
      : AuthUser(uid: user.uid, email: user.email ?? '');

  @override
  Stream<AuthUser?> authStateChanges() => _auth.authStateChanges().map(_toUser);

  @override
  AuthUser? get currentUser => _toUser(_auth.currentUser);

  @override
  Future<void> signIn(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
    } on fb.FirebaseAuthException catch (e) {
      throw AuthException(authErrorMessage(e.code));
    }
  }

  @override
  Future<void> signUp(String email, String password) async {
    try {
      await _auth.createUserWithEmailAndPassword(email: email, password: password);
    } on fb.FirebaseAuthException catch (e) {
      throw AuthException(authErrorMessage(e.code));
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> deleteAccount(String password) async {
    final user = _auth.currentUser;
    if (user == null) throw const AuthException('로그인 상태가 아니에요');
    final email = user.email;
    if (email == null || email.isEmpty) {
      throw const AuthException('이메일을 확인할 수 없어요');
    }
    try {
      await user.reauthenticateWithCredential(
        fb.EmailAuthProvider.credential(email: email, password: password),
      );
      await user.delete();
    } on fb.FirebaseAuthException catch (e) {
      throw AuthException(authErrorMessage(e.code));
    }
  }
}
