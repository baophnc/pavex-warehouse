import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app.dart';
import 'password_screens.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _hidePassword = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.session(context).login(_email.text, _password.text);
    } catch (error) {
      if (mounted) setState(() => _error = loginErrorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => ForgotPasswordScreen(email: _email.text.trim())),
    );
    if (email != null && mounted) {
      _email.text = email;
      _password.clear();
    }
  }

  Future<void> _editServer() async {
    final config = AppScope.configOf(context);
    final controller = TextEditingController(text: config.baseUrl);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Địa chỉ máy chủ'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: 'http://192.168.1.10:8080'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Lưu')),
        ],
      ),
    );
    controller.dispose();
    if (value != null) {
      await config.setBaseUrl(value);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = AppScope.configOf(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 64,
                        height: 64,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(18)),
                        child: const Icon(Icons.local_shipping_rounded, color: Colors.white, size: 34),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('Pavex Hiện trường', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    Text(
                      'Ứng dụng cho bưu tá, nhân viên bưu cục và tài xế trung chuyển.',
                      style: TextStyle(color: Theme.of(context).colorScheme.outline),
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Email công việc', prefixIcon: Icon(Icons.mail_outline)),
                      validator: (value) => value != null && value.contains('@') ? null : 'Nhập email hợp lệ',
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      obscureText: _hidePassword,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Mật khẩu',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_hidePassword ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setState(() => _hidePassword = !_hidePassword),
                        ),
                      ),
                      validator: (value) => value != null && value.isNotEmpty ? null : 'Nhập mật khẩu',
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
                          : const Text('Đăng nhập'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(onPressed: _busy ? null : _forgotPassword, child: const Text('Quên mật khẩu?')),
                    if (kIsWeb) ...[
                      const SizedBox(height: 16),
                      const WebBuildNote(),
                    ],
                    // Release builds talk only to the HTTPS address they were built with.
                    if (config.editable) ...[
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _editServer,
                        icon: const Icon(Icons.dns_outlined, size: 18),
                        label: Text('Máy chủ: ${config.baseUrl}', overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The browser build is for trying the app out: say what only the phone app does.
class WebBuildNote extends StatelessWidget {
  const WebBuildNote({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final session = AppScope.session(context);
    return Card(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Đây là bản web để dùng thử. Quét mã bằng camera chỉ chạy khi trình duyệt cho phép camera; '
              'gửi vị trí chuyến xe chỉ chạy khi tab đang mở. Làm việc thật hãy dùng app trên điện thoại.'
              '${session.storageAvailable ? '' : ' Trình duyệt này không lưu được phiên đăng nhập (trang không mở qua '
                  'https:// hoặc localhost), tải lại trang sẽ phải đăng nhập lại.'}',
              style: TextStyle(color: scheme.onSecondaryContainer),
            ),
            TextButton.icon(
              onPressed: () => launchUrl(Uri.base.resolve('download/'), webOnlyWindowName: '_blank'),
              icon: const Icon(Icons.android, size: 18),
              label: const Text('Tải app Android'),
            ),
          ],
        ),
      ),
    );
  }
}
