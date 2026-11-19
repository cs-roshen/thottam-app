import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'app/settings.dart';
import 'core/prefs/device_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // read before the first frame, so it is already in the chosen language
  final store = await FileDeviceStore.open(
    await getApplicationSupportDirectory(),
  );
  runApp(
    ProviderScope(
      overrides: [deviceStoreProvider.overrideWithValue(store)],
      child: const ThottamApp(),
    ),
  );
}
