import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import '../core/rules_manager.dart';

class RulesPage extends StatefulWidget {
  const RulesPage({super.key});

  @override
  State<RulesPage> createState() => _RulesPageState();
}

class _RulesPageState extends State<RulesPage> {
  final LocalRuleManager _rulesManager = LocalRuleManager();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  Future<void> _loadRules() async {
    setState(() => _isLoading = true);
    await _rulesManager.init();
    setState(() => _isLoading = false);
  }

  Future<void> _toggleRule(String ruleId, bool currentEnabled) async {
    final rules = _rulesManager.getLocalRules();
    final rule = rules.firstWhere((r) => r.rule.id == ruleId);
    final updatedRule = LocalRule(rule: rule.rule, enabled: !currentEnabled);
    await _rulesManager.updateRule(ruleId, updatedRule);
    setState(() {});
  }

  Future<void> _deleteRule(String ruleId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Rule'),
        content: const Text('Are you sure you want to delete this rule?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _rulesManager.deleteRule(ruleId);
      setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Rule deleted')));
      }
    }
  }

  Future<void> _exportRules() async {
    try {
      // Generate the export JSON content
      final jsonContent = _rulesManager.exportToJson(null);

      // Generate default filename with timestamp
      final formattedTimestamp = DateTime.now().toIso8601String().substring(
        0,
        10,
      );
      final defaultFileName = 'LinkPure_$formattedTimestamp.json';

      // Convert string to Uint8List for mobile platforms
      final bytes = Uint8List.fromList(utf8.encode(jsonContent));

      // Let user choose where to save the file
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Rules Export',
        fileName: defaultFileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes, // Required for mobile platforms
      );

      if (outputPath == null) {
        return; // User canceled
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rules exported successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  Future<void> _importRules() async {
    try {
      // Pick a JSON file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        allowMultiple: false,
        withData: true, // Important for web platform
      );

      if (result == null || result.files.isEmpty) {
        return; // User canceled
      }

      final file = result.files.first;

      // Use bytes for all platforms (unified approach)
      if (file.bytes == null) {
        throw Exception('Unable to read file: bytes not available');
      }

      final jsonString = utf8.decode(file.bytes!);
      await _rulesManager.importFromJson(jsonString, merge: true);

      await _loadRules();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rules imported successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rules Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: _importRules,
            tooltip: 'Import Rules',
          ),
          IconButton(
            icon: const Icon(Icons.save_alt),
            onPressed: _exportRules,
            tooltip: 'Export Rules',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildRulesList(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await context.push('/rules/edit');
          if (result == true) {
            await _loadRules(); // Reload rules
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Rule'),
      ),
    );
  }

  Widget _buildRulesList() {
    final localRules = _rulesManager.getLocalRules();

    if (localRules.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.rule_outlined, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No custom rules yet',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              'Click the button below to add a rule',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: localRules.length,
      itemBuilder: (context, index) {
        final localRule = localRules[index];
        final rule = localRule.rule;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: ListTile(
            leading: Icon(
              localRule.enabled ? Icons.check_circle : Icons.cancel,
              color: localRule.enabled ? Colors.green : Colors.grey,
            ),
            title: Text(
              rule.regexFilter,
              style: const TextStyle(fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                if (rule.regexSubstitution != null)
                  Text(
                    'Replace: ${rule.regexSubstitution}',
                    style: const TextStyle(fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (rule.removeParams != null)
                  Text(
                    'Remove params: ${rule.removeParams!.join(", ")}',
                    style: const TextStyle(fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: localRule.enabled,
                  onChanged: (value) => _toggleRule(rule.id, localRule.enabled),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') {
                      context
                          .push(
                            '/rules/edit?id=${Uri.encodeComponent(rule.id)}',
                          )
                          .then((result) async {
                            if (result == true) {
                              await _loadRules(); // Reload rules
                            }
                          });
                    } else if (value == 'delete') {
                      _deleteRule(rule.id);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit, size: 20),
                          SizedBox(width: 8),
                          Text('Edit'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, size: 20, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Delete', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
