import 'package:flutter/material.dart';

import '../../data/sync/auth_service.dart';
import '../../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  final AuthService authService;
  const LoginScreen({super.key, required this.authService});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
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

  Widget _tab(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              color: active ? AppColors.ink : AppColors.inkTertiary,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('English Helper',
                    style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(height: 6),
                const Text(
                  '저장한 단어를 모든 기기에서 보려면 로그인하세요.',
                  style: TextStyle(fontSize: 14, color: AppColors.inkSecondary),
                ),
                const SizedBox(height: 28),
                Row(children: [
                  _tab('로그인', !_signUpMode,
                      () => setState(() { _signUpMode = false; _error = null; })),
                  _tab('회원가입', _signUpMode,
                      () => setState(() { _signUpMode = true; _error = null; })),
                ]),
                const SizedBox(height: 20),
                TextField(
                  key: const Key('login-email'),
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: '이메일'),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('login-password'),
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '비밀번호'),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  key: const Key('login-submit'),
                  onPressed: _busy ? null : _submit,
                  child: Text(_signUpMode ? '가입하고 시작하기' : '로그인'),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 20,
                  child: Text(
                    _error ?? '',
                    style: const TextStyle(fontSize: 13, color: Color(0xFFCC5C43)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
