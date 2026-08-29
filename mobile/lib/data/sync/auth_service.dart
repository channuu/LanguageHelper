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
}
