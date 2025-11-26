import 'package:flutter/material.dart';
import 'package:ulid/ulid.dart';
import '../core/rules_manager.dart';
import '../models/rule.dart';

class RuleEditPage extends StatefulWidget {
  final String? ruleId;

  const RuleEditPage({super.key, this.ruleId});

  @override
  State<RuleEditPage> createState() => _RuleEditPageState();
}

class _RuleEditPageState extends State<RuleEditPage> {
  final _formKey = GlobalKey<FormState>();
  final LocalRuleManager _rulesManager = LocalRuleManager();

  late TextEditingController _regexFilterController;
  late TextEditingController _regexSubstitutionController;
  late TextEditingController _testUrlController;

  String? _generatedId;
  String? _testResult;
  bool _isLoading = true;
  bool _enabled = true;
  bool _isEditMode = false;

  @override
  void initState() {
    super.initState();
    _regexFilterController = TextEditingController();
    _regexSubstitutionController = TextEditingController();
    _testUrlController = TextEditingController();
    _loadRule();
  }

  Future<void> _loadRule() async {
    await _rulesManager.init();

    if (widget.ruleId != null) {
      _isEditMode = true;
      final rules = _rulesManager.getLocalRules();
      final localRule = rules.firstWhere((r) => r.rule.id == widget.ruleId);

      _generatedId = localRule.rule.id;
      _regexFilterController.text = localRule.rule.regexFilter;
      _regexSubstitutionController.text =
          localRule.rule.regexSubstitution ?? '';
      _enabled = localRule.enabled;
    } else {
      // Generate new ID (using sortable ULID)
      _generatedId = Ulid().toString();
    }

    setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _regexFilterController.dispose();
    _regexSubstitutionController.dispose();
    _testUrlController.dispose();
    super.dispose();
  }

  void _testRule() {
    // If regex or test URL is empty, don't show any message
    if (_regexFilterController.text.trim().isEmpty ||
        _testUrlController.text.trim().isEmpty) {
      setState(() => _testResult = null);
      return;
    }

    try {
      final regex = RegExp(_regexFilterController.text.trim());
      final testUrl = _testUrlController.text.trim();
      final match = regex.firstMatch(testUrl);

      if (match == null) {
        setState(() => _testResult = '✗ No match');
        return;
      }

      if (_regexSubstitutionController.text.trim().isEmpty) {
        setState(() => _testResult = '✓ Match successful (no substitution)');
        return;
      }

      String result = _regexSubstitutionController.text.trim();
      for (int i = 0; i <= match.groupCount; i++) {
        result = result.replaceAll('\$$i', match.group(i) ?? '');
      }

      setState(() => _testResult = '✓ Result: $result');
    } catch (e) {
      setState(() => _testResult = 'Error: $e');
    }
  }

  Future<void> _saveRule() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    try {
      final rule = Rule(
        id: _generatedId!,
        regexFilter: _regexFilterController.text.trim(),
        regexSubstitution: _regexSubstitutionController.text.trim().isEmpty
            ? null
            : _regexSubstitutionController.text.trim(),
      );

      final localRule = LocalRule(rule: rule, enabled: _enabled);

      if (_isEditMode) {
        await _rulesManager.updateRule(widget.ruleId!, localRule);
      } else {
        await _rulesManager.newRule(localRule);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditMode ? 'Rule updated' : 'Rule created'),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditMode ? 'Edit Rule' : 'Add Rule')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _regexFilterController,
                      decoration: const InputDecoration(
                        labelText: 'Regular Expression Match *',
                        helperText: 'Regular expression to match URLs',
                        hintText: r'^https://youtube\.com/shorts/([^?]+)',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        final trimmed = value.trim();
                        if (trimmed != value) {
                          _regexFilterController.value = TextEditingValue(
                            text: trimmed,
                            selection: TextSelection.collapsed(
                              offset: trimmed.length,
                            ),
                          );
                        }
                        _testRule();
                      },
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a regular expression';
                        }
                        try {
                          RegExp(value.trim());
                        } catch (e) {
                          return 'Invalid regular expression';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _regexSubstitutionController,
                      decoration: const InputDecoration(
                        labelText: 'Replace With',
                        helperText:
                            'Replacement URL format (optional, supports capture groups \$1, \$2)',
                        hintText: r'https://youtube.com/watch?v=$1',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        final trimmed = value.trim();
                        if (trimmed != value) {
                          _regexSubstitutionController.value = TextEditingValue(
                            text: trimmed,
                            selection: TextSelection.collapsed(
                              offset: trimmed.length,
                            ),
                          );
                        }
                        _testRule();
                      },
                    ),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text(
                      'Test Rule',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _testUrlController,
                      decoration: const InputDecoration(
                        labelText: 'Test URL',
                        hintText: 'https://youtube.com/shorts/abc123',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        final trimmed = value.trim();
                        if (trimmed != value) {
                          _testUrlController.value = TextEditingValue(
                            text: trimmed,
                            selection: TextSelection.collapsed(
                              offset: trimmed.length,
                            ),
                          );
                        }
                        _testRule();
                      },
                    ),
                    if (_testResult != null) ...[
                      const SizedBox(height: 12),
                      Builder(
                        builder: (context) {
                          final isSuccess = _testResult!.startsWith('✓');
                          final isDarkMode =
                              Theme.of(context).brightness == Brightness.dark;
                          final textColor = isSuccess
                              ? (isDarkMode
                                    ? const Color(0xFF4ADE80)
                                    : Colors.green[800])
                              : (isDarkMode
                                    ? const Color(0xFFF87171)
                                    : Colors.red[800]);
                          return Card(
                            color: isSuccess
                                ? (isDarkMode
                                      ? Colors.green.withOpacity(0.15)
                                      : Colors.green[50])
                                : (isDarkMode
                                      ? Colors.red.withOpacity(0.15)
                                      : Colors.red[50]),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Icon(
                                    isSuccess
                                        ? Icons.check_circle
                                        : Icons.error,
                                    color: isSuccess
                                        ? (isDarkMode
                                              ? const Color(0xFF4ADE80)
                                              : Colors.green)
                                        : (isDarkMode
                                              ? const Color(0xFFF87171)
                                              : Colors.red),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _testResult!,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: textColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text('Enable this rule'),
                      value: _enabled,
                      onChanged: (value) {
                        setState(() => _enabled = value);
                      },
                      contentPadding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _saveRule,
                            child: Text(_isEditMode ? 'Update' : 'Create'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Builder(
                      builder: (context) {
                        final isDarkMode =
                            Theme.of(context).brightness == Brightness.dark;
                        return Card(
                          color: isDarkMode
                              ? Colors.blue.withOpacity(0.15)
                              : Colors.blue[50],
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      size: 20,
                                      color: isDarkMode
                                          ? const Color(0xFF60A5FA)
                                          : Colors.blue[700],
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Tips',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: isDarkMode
                                            ? const Color(0xFF60A5FA)
                                            : Colors.blue[700],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '• Regular expressions are used to match URLs to be processed\n'
                                  '• Use parentheses () to create capture groups\n'
                                  '• Use \$1, \$2, etc. in replacement to reference capture groups\n'
                                  '• If replacement is not filled, it will only match without modification',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDarkMode
                                        ? const Color(0xFF93C5FD)
                                        : Colors.blue[900],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    ExpansionTile(
                      title: const Text('Examples'),
                      children: [
                        _buildExample(
                          'Convert YouTube Shorts',
                          r'^https://youtube\.com/shorts/([^?]+)',
                          r'https://youtube.com/watch?v=$1',
                        ),
                        _buildExample(
                          'Simplify Amazon Links',
                          r'^https://www\.amazon\..+/dp/([A-Z0-9]+)',
                          r'https://amazon.com/dp/$1',
                        ),
                        _buildExample(
                          'Clean Twitter Links',
                          r'^https://(twitter|x)\.com/(.+)',
                          r'https://x.com/$2',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildExample(String title, String filter, String substitution) {
    return ListTile(
      dense: true,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Match: $filter', style: const TextStyle(fontSize: 12)),
          Text('Replace: $substitution', style: const TextStyle(fontSize: 12)),
        ],
      ),
      trailing: TextButton.icon(
        icon: const Icon(Icons.input, size: 18),
        label: const Text('Use'),
        onPressed: () {
          setState(() {
            _regexFilterController.text = filter;
            _regexSubstitutionController.text = substitution;
          });
          _testRule();
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Example applied to form')));
        },
      ),
    );
  }
}
