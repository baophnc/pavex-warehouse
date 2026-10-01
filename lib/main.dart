import 'package:flutter/material.dart';

import 'app.dart';
import 'core/api.dart';
import 'core/config.dart';
import 'core/session.dart';
import 'data/repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = await AppConfig.load();
  final session = SessionController(PavexRepository(ApiClient(config)));
  await session.restore();
  runApp(PavexWarehouseApp(session: session, config: config));
}
