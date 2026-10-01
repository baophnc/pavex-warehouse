import 'package:flutter/material.dart';

import '../app.dart';
import 'widgets.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = AppScope.session(context);
    final config = AppScope.configOf(context);
    final user = session.user;
    return Scaffold(
      appBar: AppBar(title: const Text('Tài khoản')),
      body: user == null
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(session.profile?.name ?? user.email, style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('${user.email}\n${user.role.label}'),
                    isThreeLine: true,
                  ),
                ),
                const SectionTitle('Bưu cục làm việc'),
                if ((session.hubScope?.hubs ?? const []).isEmpty)
                  const Card(child: ListTile(title: Text('Chưa được phân bưu cục. Liên hệ trưởng bưu cục.')))
                else
                  Card(
                    child: Column(
                      children: [
                        for (final hub in session.hubScope!.hubs)
                          ListTile(
                            leading: Icon(hub.id == session.currentHub?.id ? Icons.radio_button_checked : Icons.radio_button_off),
                            title: Text(hub.name),
                            subtitle: Text('${hub.code}${hub.primary ? ' · bưu cục chính' : ''}'),
                            onTap: () => session.selectHub(hub),
                          ),
                      ],
                    ),
                  ),
                const SectionTitle('Ứng dụng'),
                Card(
                  child: ListTile(leading: const Icon(Icons.dns_outlined), title: const Text('Máy chủ'), subtitle: Text(config.baseUrl)),
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () async {
                    if (!await confirm(context, title: 'Đăng xuất?', message: 'Bạn sẽ cần đăng nhập lại để tiếp tục làm việc.', action: 'Đăng xuất')) {
                      return;
                    }
                    if (!context.mounted) return;
                    Navigator.of(context).popUntil((route) => route.isFirst);
                    await session.logout();
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('Đăng xuất'),
                ),
              ],
            ),
    );
  }
}
