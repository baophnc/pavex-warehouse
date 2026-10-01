import 'package:flutter/material.dart';

import '../app.dart';
import '../core/api.dart';
import 'widgets.dart';

/// Sign-in failures in the worker's words (the server answers 401 for several reasons).
String loginErrorText(Object error) {
  if (error is ApiException) {
    switch (error.code) {
      case 'invalid_credentials':
        return 'Email hoặc mật khẩu không đúng.';
      case 'temporary_password_expired':
        return 'Mật khẩu tạm đã hết hạn. Bấm “Quên mật khẩu” để đặt mật khẩu mới.';
      case 'email_not_verified':
        return 'Tài khoản chưa được kích hoạt. Bấm “Quên mật khẩu” để đặt mật khẩu qua email.';
      case 'account_locked':
        return 'Đăng nhập sai quá nhiều lần nên tài khoản tạm khoá. Thử lại sau ít phút.';
      case 'account_suspended':
      case 'account_disabled':
        return 'Tài khoản đang bị khoá. Liên hệ trưởng bưu cục hoặc quản trị viên.';
    }
  }
  return errorText(error);
}

String _passwordErrorText(Object error) {
  if (error is ApiException) {
    switch (error.code) {
      case 'invalid_current_password':
        return 'Mật khẩu tạm không đúng.';
      case 'password_unchanged':
        return 'Mật khẩu mới phải khác mật khẩu tạm.';
      case 'invalid_password_reset_token':
        return 'Mã trong email không đúng hoặc đã hết hạn (1 giờ). Hãy gửi lại email.';
    }
  }
  return errorText(error);
}

String? _newPasswordRule(String? value) =>
    value != null && value.length >= 8 && value.length <= 128 ? null : 'Mật khẩu mới dài 8–128 ký tự';

/// The reset link is `…/reset-password?token=…`; accept the whole link or just the token.
String extractResetToken(String input) {
  final text = input.trim();
  final uri = Uri.tryParse(text);
  return uri?.queryParameters['token'] ?? text;
}

/// First sign-in with the temporary password an administrator issued: a new password is required.
class FirstPasswordScreen extends StatefulWidget {
  const FirstPasswordScreen({super.key});

  @override
  State<FirstPasswordScreen> createState() => _FirstPasswordScreenState();
}

class _FirstPasswordScreenState extends State<FirstPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.read(context).changePassword(_current.text, _password.text);
    } catch (error) {
      if (mounted) setState(() => _error = _passwordErrorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.session(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Đặt mật khẩu của bạn'),
        actions: [TextButton(onPressed: _busy ? null : session.logout, child: const Text('Đăng xuất'))],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Tài khoản ${session.user?.email ?? ''} đang dùng mật khẩu tạm do quản trị viên cấp. '
                  'Hãy đặt mật khẩu riêng trước khi bắt đầu làm việc.',
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _current,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Mật khẩu tạm được cấp', prefixIcon: Icon(Icons.lock_clock_outlined)),
                  validator: (value) => value != null && value.isNotEmpty ? null : 'Nhập mật khẩu tạm',
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Mật khẩu mới', prefixIcon: Icon(Icons.lock_outline)),
                  validator: _newPasswordRule,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _confirm,
                  obscureText: true,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(labelText: 'Nhập lại mật khẩu mới', prefixIcon: Icon(Icons.lock_outline)),
                  validator: (value) => value == _password.text ? null : 'Hai mật khẩu mới chưa trùng nhau',
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                      : const Text('Lưu mật khẩu mới'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Forgot password inside the app: email a reset link, then paste the link (or its code) here.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.email = ''});

  final String email;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailForm = GlobalKey<FormState>();
  final _resetForm = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.email);
  final _token = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _sent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _token.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = _passwordErrorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    if (!_emailForm.currentState!.validate()) return;
    await _run(() async {
      await AppScope.repository(context).forgotPassword(_email.text);
      if (mounted) setState(() => _sent = true);
    });
  }

  Future<void> _reset() async {
    if (!_resetForm.currentState!.validate()) return;
    await _run(() async {
      await AppScope.repository(context).resetPassword(extractResetToken(_token.text), _password.text);
      if (!mounted) return;
      showMessage(context, 'Đã đặt mật khẩu mới. Hãy đăng nhập bằng mật khẩu vừa đặt.');
      Navigator.of(context).pop(_email.text.trim());
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Quên mật khẩu')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Form(
                  key: _emailForm,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('1. Nhập email công việc. Pavex gửi một email có liên kết đặt mật khẩu (hiệu lực 1 giờ).'),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _email,
                        enabled: !_sent,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'Email công việc', prefixIcon: Icon(Icons.mail_outline)),
                        validator: (value) => value != null && value.contains('@') ? null : 'Nhập email hợp lệ',
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton(
                        onPressed: _busy ? null : _send,
                        child: Text(_sent ? 'Gửi lại email' : 'Gửi email đặt mật khẩu'),
                      ),
                    ],
                  ),
                ),
                if (_sent) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Nếu email có trong hệ thống, thư đã được gửi. Mở thư, bấm giữ liên kết để sao chép, '
                    'rồi dán vào ô dưới đây. Bạn cũng có thể mở liên kết trên máy tính.',
                  ),
                  const Divider(height: 36),
                  Form(
                    key: _resetForm,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('2. Dán liên kết trong email và đặt mật khẩu mới.'),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _token,
                          decoration: const InputDecoration(labelText: 'Liên kết hoặc mã trong email', prefixIcon: Icon(Icons.link)),
                          validator: (value) => value != null && extractResetToken(value).isNotEmpty ? null : 'Dán liên kết trong email',
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _password,
                          obscureText: true,
                          decoration: const InputDecoration(labelText: 'Mật khẩu mới', prefixIcon: Icon(Icons.lock_outline)),
                          validator: _newPasswordRule,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _confirm,
                          obscureText: true,
                          decoration: const InputDecoration(labelText: 'Nhập lại mật khẩu mới', prefixIcon: Icon(Icons.lock_outline)),
                          validator: (value) => value == _password.text ? null : 'Hai mật khẩu mới chưa trùng nhau',
                        ),
                        const SizedBox(height: 14),
                        FilledButton(onPressed: _busy ? null : _reset, child: const Text('Lưu mật khẩu mới')),
                      ],
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
              ],
            ),
          ),
        ),
      );
}
