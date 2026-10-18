import 'package:flutter/material.dart';

import 'core/config.dart';
import 'core/session.dart';
import 'data/repository.dart';
import 'ui/login_screen.dart';
import 'ui/password_screens.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

/// Gives every screen the session and the repository.
class AppScope extends InheritedNotifier<SessionController> {
  const AppScope({super.key, required SessionController session, required this.config, required super.child})
      : super(notifier: session);

  final AppConfig config;

  static AppScope _of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  static SessionController session(BuildContext context) => _of(context).notifier!;

  /// Reads the session without rebuilding on changes; safe in initState and callbacks.
  static SessionController read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;

  static PavexRepository repository(BuildContext context) => read(context).repository;

  static AppConfig configOf(BuildContext context) => _of(context).config;
}

class PavexWarehouseApp extends StatelessWidget {
  const PavexWarehouseApp({super.key, required this.session, required this.config});

  final SessionController session;
  final AppConfig config;

  @override
  Widget build(BuildContext context) => AppScope(
        session: session,
        config: config,
        child: MaterialApp(
          title: 'Pavex Hiện trường',
          debugShowCheckedModeBanner: false,
          theme: pavexTheme(Brightness.light),
          darkTheme: pavexTheme(Brightness.dark),
          home: ListenableBuilder(
            listenable: session,
            builder: (context, _) => !session.signedIn
                ? const LoginScreen()
                : session.passwordChangeRequired
                    ? const FirstPasswordScreen()
                    : const AppShell(),
          ),
        ),
      );
}
