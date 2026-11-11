import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/controller.dart';
import 'app/settings.dart';
import 'core/error_log.dart';
import 'ui/title_bar.dart';
import 'ui/nav.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Errors nobody handled go to the error log on this device — every build, from the first moment —
  // and, where usage reporting is on, into the usage record. Nothing is shown to the person.
  AppController? controller;
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    previous?.call(details);
    errorLog.error('app', details.exception, stack: details.stack, context: details.context?.toDescription());
    controller?.usage.recordError(details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    errorLog.error('app', error, stack: stack);
    controller?.usage.recordError(error, stack);
    return false; // still reported the usual way
  };
  controller = await AppController.create();

  // Web build only (demos and screenshots): `?theme=light&page=devices&mac=…&hex=…` opens a given view.
  final q = kIsWeb ? Uri.base.queryParameters : const <String, String>{};
  final theme = ThemeChoice.values.where((v) => v.name == q['theme']).firstOrNull;
  if (theme != null) controller.settings.update((s) => s.themeChoice = theme);
  final page = PageId.values.where((v) => v.name == q['page']).firstOrNull;

  // Before the window first shows (it waits for the first frame), so it never flashes the system's.
  unawaited(TitleBar.match(
    dark: TitleBar.isDark(controller.settings.themeChoice, PlatformDispatcher.instance.platformBrightness),
  ));
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
            // The Windows title bar follows the theme as it changes (Settings, or the system on Auto).
            builder: (context, child) {
              unawaited(TitleBar.match(dark: Theme.of(context).brightness == Brightness.dark));
              return child!;
            },
            home: Shell(initialPage: initialPage, initialMac: initialMac, initialHex: initialHex),
          ),
        ),
      );
}
