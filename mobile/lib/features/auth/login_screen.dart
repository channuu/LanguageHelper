import 'package:flutter/material.dart';

import '../../data/sync/auth_service.dart';
import '../../theme/app_theme.dart';

/// 목업 `English Helper UI.dc.html`의 아트보드 2a(앱 로그인)를 따른다.
/// 목업에만 있고 아직 구현이 없는 세 가지 — Google 로그인, 비밀번호 찾기,
/// 로그인 없이 둘러보기 — 는 넣지 않았다. 눌러도 아무 일도 없는 버튼은
/// 없는 것만 못하고, 특히 '둘러보기'는 로그인 필수라는 설계와 어긋난다.
class LoginScreen extends StatefulWidget {
  final AuthService authService;
  const LoginScreen({super.key, required this.authService});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

/// 목업이 이 화면에서만 쓰는 값들. 전역 토큰으로 올리는 건 다른 화면도
/// 같은 값을 쓸 때 하는 편이 낫다.
class _Mock {
  static const tabTrack = Color(0xFFE5E8F0);
  static const fieldBorder = Color(0xFFDCE1EA);
  static const error = Color(0xFFC0432C);
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signUpMode = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = '이메일과 비밀번호를 입력해 주세요');
      return;
    }
    if (_signUpMode && password.length < 6) {
      setState(() => _error = authErrorMessage('weak-password'));
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_signUpMode) {
        await widget.authService.signUp(email, password);
      } else {
        await widget.authService.signIn(email, password);
      }
      // 성공하면 AuthGate가 인증 스트림을 보고 화면을 바꾼다.
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '로그인에 실패했어요');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setMode(bool signUp) {
    setState(() {
      _signUpMode = signUp;
      _error = null;
    });
  }

  Widget _brand() {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: const Text(
            'E',
            style: TextStyle(
              fontFamily: AppFonts.display,
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: AppColors.ink,
            ),
          ),
        ),
        const SizedBox(width: 10),
        const Text(
          'English Helper',
          style: TextStyle(
            fontFamily: AppFonts.display,
            fontWeight: FontWeight.w600,
            fontSize: 15,
            letterSpacing: -0.15,
            color: AppColors.ink,
          ),
        ),
      ],
    );
  }

  Widget _tab(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: active
                ? const [
                    BoxShadow(
                      color: Color(0x1F14161F),
                      blurRadius: 3,
                      offset: Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: AppFonts.display,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: active ? AppColors.ink : AppColors.inkTertiary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: AppFonts.mono,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.0,
        color: AppColors.inkQuaternary,
      ),
    );
  }

  Widget _input({
    required Key key,
    required TextEditingController controller,
    required String hint,
    bool obscure = false,
    TextInputType? keyboardType,
  }) {
    const border = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
      borderSide: BorderSide(color: _Mock.fieldBorder),
    );
    return TextField(
      key: key,
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      autocorrect: false,
      style: const TextStyle(
        fontFamily: AppFonts.display,
        fontSize: 15,
        color: AppColors.ink,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          fontFamily: AppFonts.display,
          fontSize: 15,
          color: AppColors.inkFaint,
        ),
        filled: true,
        fillColor: AppColors.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        enabledBorder: border,
        border: border,
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: AppColors.accent, width: 1.6),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _signUpMode ? '단어를 모으는\n계정을 만들어요' : '다시 이어서\n복습할까요';
    final subtitle = _signUpMode
        ? '이메일만 있으면 됩니다. 브라우저에서 저장한 단어가 바로 이어집니다.'
        : '저장한 단어를 모든 기기에서 보려면 로그인하세요.';

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 34),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _brand(),
              const SizedBox(height: 30),
              Text(
                title,
                style: const TextStyle(
                  fontFamily: AppFonts.display,
                  fontSize: 32,
                  fontWeight: FontWeight.w600,
                  height: 1.18,
                  letterSpacing: -0.48,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                subtitle,
                style: const TextStyle(
                  fontFamily: AppFonts.display,
                  fontSize: 13.5,
                  height: 1.7,
                  color: AppColors.inkTertiary,
                ),
              ),
              const SizedBox(height: 26),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: _Mock.tabTrack,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  _tab('로그인', !_signUpMode, () => _setMode(false)),
                  const SizedBox(width: 4),
                  _tab('회원가입', _signUpMode, () => _setMode(true)),
                ]),
              ),
              const SizedBox(height: 22),
              _fieldLabel('EMAIL'),
              const SizedBox(height: 8),
              _input(
                key: const Key('login-email'),
                controller: _email,
                hint: 'you@example.com',
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 14),
              _fieldLabel('PASSWORD'),
              const SizedBox(height: 8),
              _input(
                key: const Key('login-password'),
                controller: _password,
                hint: _signUpMode ? '6자 이상' : '비밀번호',
                obscure: true,
              ),
              Container(
                constraints: const BoxConstraints(minHeight: 20),
                margin: const EdgeInsets.only(top: 10),
                alignment: Alignment.centerLeft,
                child: Text(
                  _error ?? '',
                  style: const TextStyle(
                    fontFamily: AppFonts.display,
                    fontSize: 12.5,
                    color: _Mock.error,
                  ),
                ),
              ),
              SizedBox(
                height: 52,
                child: FilledButton(
                  key: const Key('login-submit'),
                  onPressed: _busy ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.ink,
                    // 진행 중에는 목업처럼 색을 옅게 두고 라벨로 알린다.
                    disabledBackgroundColor: const Color(0x73FB864D),
                    disabledForegroundColor: AppColors.ink,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: AppFonts.display,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text(_busy
                      ? '연결 중…'
                      : _signUpMode
                          ? '가입하고 시작하기'
                          : '로그인'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
