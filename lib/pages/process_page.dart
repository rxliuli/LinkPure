import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../services/notification_service.dart';
import '../core/rules_manager.dart';
import '../core/url_cleaner.dart';

enum ProcessStatus { processing, success, error }

enum ErrorType {
  notUrl,
  noRulesMatched,
  circularRedirect,
  infiniteRedirect,
  unknown,
}

class ProcessPage extends StatefulWidget {
  final String? url;

  const ProcessPage({super.key, this.url});

  @override
  State<ProcessPage> createState() => _ProcessPageState();
}

class _ProcessPageState extends State<ProcessPage> {
  ProcessStatus _status = ProcessStatus.processing;
  ErrorType? _errorType;
  String? _result;
  String? _errorMessage;
  final RulesManager _rulesManager = RulesManager();

  @override
  void initState() {
    super.initState();
    _processUrl();
  }

  @override
  void didUpdateWidget(ProcessPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-process if URL parameter changed
    if (widget.url != oldWidget.url) {
      setState(() {
        _status = ProcessStatus.processing;
        _errorType = null;
        _result = null;
        _errorMessage = null;
      });
      _processUrl();
    }
  }

  Future<void> _processUrl() async {
    try {
      final inputText = widget.url;

      // Check if input is provided
      if (inputText == null || inputText.isEmpty) {
        _setError(ErrorType.notUrl, 'No text provided');
        return;
      }

      // Check if input is a valid URL
      if (!UrlCleaner.isValidUrl(inputText)) {
        _setError(ErrorType.notUrl, 'The shared text is not a valid URL');
        return;
      }

      // Load rules
      await _rulesManager.init();
      final rules = await _rulesManager.getEnabledRules();

      if (rules.isEmpty) {
        _setError(ErrorType.noRulesMatched, 'No rules available');
        return;
      }

      // Clean URL with rules
      final cleaner = UrlCleaner(rules: rules);
      final result = cleaner.check(inputText);

      switch (result.status) {
        case CheckStatus.matched:
          // Successfully cleaned
          await _handleSuccess(result.url);
          break;
        case CheckStatus.notMatched:
          // No rules matched
          _setError(
            ErrorType.noRulesMatched,
            'No matching rules found for this URL',
          );
          break;
        case CheckStatus.circularRedirect:
          // Circular redirect detected
          _setError(
            ErrorType.circularRedirect,
            'Circular redirect detected in the cleaning process',
          );
          break;
        case CheckStatus.infiniteRedirect:
          // Infinite redirect (max iterations exceeded)
          _setError(
            ErrorType.infiniteRedirect,
            'Maximum redirect limit exceeded',
          );
          break;
      }
    } catch (e) {
      _setError(ErrorType.unknown, 'An unexpected error occurred: $e');
    }
  }

  Future<void> _handleSuccess(String cleanedUrl) async {
    // Copy to clipboard
    await Clipboard.setData(ClipboardData(text: cleanedUrl));

    // Show notification
    await NotificationService.showNotification(
      title: 'URL Cleaned',
      body: 'Cleaned URL copied to clipboard $cleanedUrl',
    );

    if (mounted) {
      setState(() {
        _status = ProcessStatus.success;
        _result = cleanedUrl;
      });
    }
  }

  void _setError(ErrorType type, String message) {
    if (mounted) {
      setState(() {
        _status = ProcessStatus.error;
        _errorType = type;
        _errorMessage = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Processing'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.go('/'),
        ),
      ),
      body: Center(child: _buildContent()),
    );
  }

  Widget _buildContent() {
    switch (_status) {
      case ProcessStatus.processing:
        return const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('Cleaning URL...'),
          ],
        );
      case ProcessStatus.success:
        return _buildSuccessView();
      case ProcessStatus.error:
        return _buildErrorView();
    }
  }

  Widget _buildSuccessView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.check_circle, size: 60, color: Colors.green),
        const SizedBox(height: 20),
        const Text(
          'URL Cleaned!',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        const Text('Copied to clipboard'),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: SelectableText(
            _result ?? '',
            style: const TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 30),
        ElevatedButton(
          onPressed: () => context.go('/'),
          child: const Text('Done'),
        ),
      ],
    );
  }

  Widget _buildErrorView() {
    IconData icon;
    Color iconColor;
    String title;

    switch (_errorType) {
      case ErrorType.notUrl:
        icon = Icons.link_off;
        iconColor = Colors.orange;
        title = 'Not a URL';
        break;
      case ErrorType.noRulesMatched:
        icon = Icons.rule_outlined;
        iconColor = Colors.blue;
        title = 'No Rules Matched';
        break;
      case ErrorType.circularRedirect:
        icon = Icons.loop;
        iconColor = Colors.red;
        title = 'Circular Redirect';
        break;
      case ErrorType.infiniteRedirect:
        icon = Icons.all_inclusive;
        iconColor = Colors.red;
        title = 'Too Many Redirects';
        break;
      case ErrorType.unknown:
      case null:
        icon = Icons.error_outline;
        iconColor = Colors.red;
        title = 'Error';
        break;
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 60, color: iconColor),
        const SizedBox(height: 20),
        Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            _errorMessage ?? 'An error occurred',
            style: const TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 30),
        ElevatedButton(
          onPressed: () => context.go('/'),
          child: const Text('Go Back'),
        ),
      ],
    );
  }
}
