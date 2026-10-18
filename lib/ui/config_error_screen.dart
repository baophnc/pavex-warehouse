import 'package:flutter/material.dart';

import 'theme.dart';

/// Shown instead of the app when a release build has no usable server address.
class ConfigErrorApp extends StatelessWidget {
  const ConfigErrorApp({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Pavex Hiện trường',
        debugShowCheckedModeBanner: false,
        theme: pavexTheme(Brightness.light),
        darkTheme: pavexTheme(Brightness.dark),
        home: Builder(
          builder: (context) => Scaffold(
            body: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.cloud_off_rounded, size: 48, color: Theme.of(context).colorScheme.error),
                        const SizedBox(height: 16),
                        Text(
                          'Không thể kết nối máy chủ',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 10),
                        Text(message),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
