import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../app/settings.dart';
import '../core/error_log.dart';
import 'theme.dart';

/// The Windows title bar in the app's own theme, not the system's: dark when BluePulse is dark,
/// light when it is light — on Windows 11 the exact colour of the app's top bar, so the two read as
/// one; Windows 10 takes dark or light. The window code (`windows/runner`) does the painting.
abstract final class TitleBar {
  static const _channel = MethodChannel('bluepulse/window');
  static bool? _dark;

  static bool get _applies => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  /// Whether the app shows dark for [choice] while the system is [system].
  static bool isDark(ThemeChoice choice, Brightness system) => switch (choice) {
        ThemeChoice.auto => system == Brightness.dark,
        ThemeChoice.light => false,
        ThemeChoice.dark => true,
      };

  /// Matches the title bar to the app's theme; nothing happens when it already does.
  static Future<void> match({required bool dark}) async {
    if (!_applies || _dark == dark) return;
    _dark = dark;
    final t = dark ? AppTokens.dark : AppTokens.light;
    try {
      await _channel.invokeMethod<void>('setTitleBar', {
        'dark': dark,
        'caption': t.bg.toARGB32(),
        'text': t.text.toARGB32(),
        'border': t.line.toARGB32(),
      });
    } catch (e) {
      _dark = null; // tried again with the next theme change
      errorLog.warn('app', 'The title bar did not take the app\'s colours', error: e);
    }
  }
}
