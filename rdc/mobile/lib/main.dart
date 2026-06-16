/// RDC Mobile — Entry Point
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/storage/secure_storage.dart';
import 'core/storage/chat_snapshot_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SecureStorage.init();
  await ChatSnapshotService.instance.init();

  runApp(
    const ProviderScope(
      child: RdcApp(),
    ),
  );
}
