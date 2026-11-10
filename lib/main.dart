import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/controller.dart';
import 'app/settings.dart';
import 'ui/nav.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = await AppController.create();

  // Errors nobody handled go into the usage record as well as the usual output.
  final usage = controller.usage;
  if (usage.enabled) {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      usage.recordError(details.exception, details.stack);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      usage.recordError(error, stack);
      return false; // still reported the usual way
    };
  }

  // Web build only (demos and screenshots): `?theme=light&page=devices&mac=…&hex=…` opens a given view.
  final q = kIsWeb ? Uri.base.queryParameters : const <String, String>{};
  final theme = ThemeChoice.values.where((v) => v.name == q['theme']).firstOrNull;
  if (theme != null) controller.settings.update((s) => s.themeChoice = theme);
  final page = PageId.values.where((v) => v.name == q['page']).firstOrNull;

  runApp(EyeApp(controller: controller, initialPage: page, initialMac: q['mac'], initialHex: q['hex']));
  unawaited(controller.startScan());
}

class EyeApp extends StatelessWidget {
  const EyeApp({super.key, required this.controller, this.initialPage, this.initialMac, this.initialHex});

  final AppController controller;
  final PageId? initialPage;
  final String? initialMac;
  final String? initialHex;

  @override
  Widget build(BuildContext context) => AppScope(
        controller: controller,
        child: ListenableBuilder(
          listenable: controller.settings,
          builder: (context, _) => MaterialApp(
            title: kDebugMode ? 'DEV · BluePulse' : 'BluePulse',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(AppTokens.light, Brightness.light),
            darkTheme: buildTheme(AppTokens.dark, Brightness.dark),
            themeMode: switch (controller.settings.themeChoice) {
              ThemeChoice.auto => ThemeMode.system,
              ThemeChoice.light => ThemeMode.light,
              ThemeChoice.dark => ThemeMode.dark,
            },
            home: Shell(initialPage: initialPage, initialMac: initialMac, initialHex: initialHex),
          ),
        ),
      );
}
