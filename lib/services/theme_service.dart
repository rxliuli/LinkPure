import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService extends ChangeNotifier {
  static const String _themeKey = 'theme_mode';
  static const _channel = MethodChannel('com.rxliuli.linkpure/theme');
  static ThemeService? _instance;
  
  ThemeMode _themeMode = ThemeMode.system;
  
  ThemeMode get themeMode => _themeMode;
  
  ThemeService._();
  
  static ThemeService get instance {
    _instance ??= ThemeService._();
    return _instance!;
  }
  
  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final themeModeIndex = prefs.getInt(_themeKey) ?? 0;
    instance._themeMode = ThemeMode.values[themeModeIndex];

    // Sync native window appearance on initialization
    await instance._syncNativeTheme();
  }
  
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    
    _themeMode = mode;
    notifyListeners();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeKey, mode.index);

    // Sync native window appearance
    await _syncNativeTheme();
  }
  
  Future<void> _syncNativeTheme() async {
    // Only sync native window appearance on macOS
    if (kIsWeb || !Platform.isMacOS) return;
    
    try {
      String mode;
      switch (_themeMode) {
        case ThemeMode.dark:
          mode = 'dark';
          break;
        case ThemeMode.light:
          mode = 'light';
          break;
        case ThemeMode.system:
          mode = 'system';
          break;
      }
      await _channel.invokeMethod('setThemeMode', {'mode': mode});
    } catch (e) {
      debugPrint('Failed to sync native theme: $e');
    }
  }
  
  String getThemeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'System';
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
    }
  }
}
