import 'package:flutter/material.dart';

import '../app.dart';
import '../core/session.dart';
import 'account_screen.dart';
import 'cash_screen.dart';
import 'home_screen.dart';
import 'reports_screen.dart';
import 'scan_screen.dart';
import 'tasks_screen.dart';
import 'trips_screen.dart';
import 'widgets.dart';

/// Bottom tabs, tailored to what the signed-in worker does.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  void _goTo(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    final role = AppScope.session(context).user!.role;
    if (role == WorkRole.unsupported) return const _UnsupportedAccount();

    final tabs = <_Tab>[
      _Tab('Hôm nay', Icons.today_outlined, Icons.today, HomeScreen(onOpenTab: (tab) => _goTo(_indexOf(tab, role)))),
      if (role == WorkRole.driver)
        const _Tab('Chuyến', Icons.local_shipping_outlined, Icons.local_shipping, TripsScreen()),
      const _Tab('Việc', Icons.assignment_outlined, Icons.assignment, TasksScreen()),
      const _Tab('Quét', Icons.qr_code_scanner, Icons.qr_code_scanner, ScanHubScreen()),
      if (role.handlesCash) const _Tab('Tiền', Icons.payments_outlined, Icons.payments, CashScreen()),
      const _Tab('Báo cáo', Icons.insert_chart_outlined, Icons.insert_chart, ReportsScreen()),
    ];
    final index = _index.clamp(0, tabs.length - 1);

    return Scaffold(
      body: IndexedStack(index: index, children: [for (final tab in tabs) tab.screen]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: _goTo,
        destinations: [
          for (final tab in tabs)
            NavigationDestination(icon: Icon(tab.icon), selectedIcon: Icon(tab.selectedIcon), label: tab.label),
        ],
      ),
    );
  }

  /// Tab order per role; null is the home tab. Must match the list built in [build].
  static List<ShellTab?> _order(WorkRole role) => [
        null,
        if (role == WorkRole.driver) ShellTab.trips,
        ShellTab.tasks,
        ShellTab.scan,
        if (role.handlesCash) ShellTab.cash,
        ShellTab.reports,
      ];

  static int _indexOf(ShellTab tab, WorkRole role) {
    final index = _order(role).indexOf(tab);
    return index < 0 ? 0 : index;
  }
}

enum ShellTab { trips, tasks, scan, cash, reports }

class _Tab {
  const _Tab(this.label, this.icon, this.selectedIcon, this.screen);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget screen;
}

class _UnsupportedAccount extends StatelessWidget {
  const _UnsupportedAccount();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const EmptyState(
                    icon: Icons.badge_outlined,
                    title: 'Tài khoản này không dùng app bưu cục',
                    message: 'App dành cho bưu tá, nhân viên bưu cục, trưởng bưu cục và tài xế trung chuyển. '
                        'Nhân viên trụ sở vui lòng dùng trang quản trị trên máy tính.',
                  ),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AccountScreen())),
                    icon: const Icon(Icons.person_outline),
                    label: const Text('Tài khoản'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
