import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:clipboard_watcher/clipboard_watcher.dart';
import '../core/url_cleaner.dart';
import '../core/rules_manager.dart';
import 'notification_service.dart';

class ClipboardService with ClipboardListener {
  static final ClipboardService _instance = ClipboardService._internal();
  factory ClipboardService() => _instance;
  ClipboardService._internal();

  bool _isInitialized = false;
  String? _lastProcessedText;
  Timer? _debounceTimer;

  /// Initialize clipboard monitoring service (desktop only)
  static Future<void> initialize() async {
    if (!_isDesktopPlatform()) {
      debugPrint('Clipboard monitoring is only available on desktop platforms');
      return;
    }

    // Auto-start on desktop platforms
    await _instance.start();
  }

  /// Check if current platform is desktop
  static bool _isDesktopPlatform() {
    return !kIsWeb &&
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
  }

  /// Start monitoring clipboard
  Future<void> start() async {
    if (!_isDesktopPlatform()) {
      throw Exception(
        'Clipboard monitoring is only available on desktop platforms',
      );
    }

    if (_isInitialized) {
      debugPrint('Clipboard monitoring already started');
      return;
    }

    try {
      clipboardWatcher.addListener(this);
      await clipboardWatcher.start();
      _isInitialized = true;

      debugPrint('Clipboard monitoring started');
    } catch (e) {
      debugPrint('Failed to start clipboard monitoring: $e');
      rethrow;
    }
  }

  /// Stop monitoring clipboard
  Future<void> stop() async {
    if (!_isInitialized) {
      return;
    }

    try {
      clipboardWatcher.removeListener(this);
      await clipboardWatcher.stop();
      _isInitialized = false;

      _debounceTimer?.cancel();
      _lastProcessedText = null;

      debugPrint('Clipboard monitoring stopped');
    } catch (e) {
      debugPrint('Failed to stop clipboard monitoring: $e');
      rethrow;
    }
  }

  @override
  void onClipboardChanged() async {
    // Debounce to avoid processing the same content multiple times
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      await _processClipboard();
    });
  }

  /// Process clipboard content
  Future<void> _processClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();

      if (text == null || text.isEmpty) {
        return;
      }

      // Skip if it's the same as last processed text
      if (text == _lastProcessedText) {
        return;
      }

      // Check if it's a valid URL
      if (!UrlCleaner.isValidUrl(text)) {
        return;
      }

      // Get rules and process URL
      final rulesManager = RulesManager();
      await rulesManager.init();
      final rules = await rulesManager.getEnabledRules();
      final cleaner = UrlCleaner(rules: rules);
      final result = await cleaner.check(text);

      // Only process if URL was modified
      if (result.status == CheckStatus.matched && result.url != text) {
        _lastProcessedText = result.url;

        // Copy cleaned URL to clipboard
        await Clipboard.setData(ClipboardData(text: result.url));

        // Show notification
        await NotificationService.showNotification(
          title: 'URL Rewritten',
          body: _truncateUrl(result.url),
          isSuccess: true,
          payload: result.url,
        );

        debugPrint('URL rewritten and copied: ${result.url}');
      } else {
        _lastProcessedText = text;
      }
    } catch (e) {
      debugPrint('Error processing clipboard: $e');
    }
  }

  /// Truncate URL for display in notification
  String _truncateUrl(String url, {int maxLength = 60}) {
    if (url.length <= maxLength) {
      return url;
    }
    return '${url.substring(0, maxLength)}...';
  }
}
