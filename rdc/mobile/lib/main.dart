/// RDC Mobile — Entry Point
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/storage/secure_storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SecureStorage.init();

  runApp(
    const ProviderScope(
      child: RdcApp(),
    ),
  );
}
