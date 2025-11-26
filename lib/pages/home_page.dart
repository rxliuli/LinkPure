import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../core/url_cleaner.dart';

// Check if running on mobile
bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final TextEditingController _urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (_isMobile) {
      WidgetsBinding.instance.addObserver(this);
      // Check clipboard when page opens
      _checkClipboardForUrl();
    }
  }

  @override
  void dispose() {
    if (_isMobile) {
      WidgetsBinding.instance.removeObserver(this);
    }
    _urlController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Check clipboard when app comes to foreground (mobile only)
    if (_isMobile && state == AppLifecycleState.resumed) {
      _checkClipboardForUrl();
    }
  }

  Future<void> _checkClipboardForUrl() async {
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      final text = clipboardData?.text?.trim();
      if (text != null && text.isNotEmpty && UrlCleaner.isValidUrl(text)) {
        // Only update if the input is empty or different from clipboard
        if (_urlController.text.trim() != text) {
          setState(() {
            _urlController.text = text;
          });
        }
      }
    } catch (e) {
      debugPrint('Error checking clipboard: $e');
    }
  }

  void _cleanUrl() {
    final url = _urlController.text.trim();
    if (url.isNotEmpty) {
      context.push('/process?url=${Uri.encodeComponent(url)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LinkPure'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.rule),
            tooltip: 'Manage Rules',
            onPressed: () {
              context.push('/rules');
            },
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.link_off, size: 80, color: Colors.deepPurple),
              const SizedBox(height: 20),
              const Text(
                'Clean tracking parameters from URLs',
                style: TextStyle(fontSize: 18),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: TextField(
                  controller: _urlController,
                  decoration: InputDecoration(
                    hintText: 'Paste URL here...',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.link),
                    suffixIcon: _urlController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              setState(() {
                                _urlController.clear();
                              });
                            },
                          )
                        : null,
                  ),
                  onChanged: (value) {
                    setState(() {});
                  },
                  onSubmitted: (value) => _cleanUrl(),
                ),
              ),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _urlController.text.trim().isEmpty
                        ? null
                        : _cleanUrl,
                    icon: const Icon(Icons.cleaning_services),
                    label: const Text('Clean URL'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'or share a URL to this app',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              const SizedBox(height: 32),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      context.push('/rules');
                    },
                    icon: const Icon(Icons.rule),
                    label: const Text('Manage Rules'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      context.push('/settings');
                    },
                    icon: const Icon(Icons.settings),
                    label: const Text('Settings'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
