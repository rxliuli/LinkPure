import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

import '../models/rule.dart';

class RulesManager {
  final LocalRuleManager _localRules = LocalRuleManager();
  bool _initialized = false;

  Future<void> init() async {
    if (!_initialized) {
      await _localRules.init();
      _initialized = true;
    }
  }

  Future<List<Rule>> getEnabledRules() async {
    await init();
    final sharedRules = await SharedRules().getSharedRules();
    final localRules = _localRules.getLocalRules().where((rule) {
      return rule.enabled;
    }).toList();
    final enabledLocalRules = localRules.map((e) => e.rule).toList();
    final allRules = [...enabledLocalRules, ...sharedRules];
    return allRules;
  }

  LocalRuleManager get localRules => _localRules;
}

class SharedRules {
  Future<List<Rule>> getSharedRules() async {
    final jsonString = await rootBundle.loadString('assets/shared-rules.json');
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    final ruleSet = RuleSet.fromJson(json);
    return ruleSet.rules;
  }
}

class LocalRule {
  final Rule rule;
  bool enabled;

  LocalRule({required this.rule, this.enabled = true});

  factory LocalRule.fromJson(Map<String, dynamic> json) {
    return LocalRule(
      rule: Rule.fromJson(json['rule'] as Map<String, dynamic>),
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {'rule': rule.toJson(), 'enabled': enabled};
  }
}

class LocalRuleManager {
  static const String _storageKey = 'local_rules';
  List<LocalRule> _rules = [];

  LocalRuleManager();

  /// Initialize and load data from SharedPreferences
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_storageKey);
    if (jsonString != null && jsonString.isNotEmpty) {
      try {
        final List<dynamic> jsonList = jsonDecode(jsonString);
        _rules = jsonList
            .map((e) => LocalRule.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (e) {
        debugPrint('Error loading local rules: $e');
        _rules = [];
      }
    }
  }

  /// Save to SharedPreferences
  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(_rules.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKey, jsonString);
  }

  List<LocalRule> getLocalRules() {
    return List.unmodifiable(_rules);
  }

  Future<void> newRule(LocalRule rule) async {
    _rules.add(rule);
    await _save();
  }

  Future<void> updateRule(String ruleId, LocalRule updatedRule) async {
    final index = _rules.indexWhere((r) => r.rule.id == ruleId);
    if (index != -1) {
      _rules[index] = updatedRule;
      await _save();
    }
  }

  Future<void> deleteRule(String ruleId) async {
    _rules.removeWhere((r) => r.rule.id == ruleId);
    await _save();
  }

  /// Export rules to JSON string
  /// Note: Only exports regexSubstitution type rules, removeParams type rules will be skipped
  String exportToJson(List<LocalRule>? rules) {
    final rulesToExport = rules ?? _rules;
    final exportedRules = rulesToExport
        .where((r) => r.rule.regexSubstitution != null)
        .map((r) => ExportedRule.fromLocalRule(r))
        .toList();
    return jsonEncode(exportedRules.map((e) => e.toJson()).toList());
  }

  /// Export rules to file
  /// If [useTemporaryDirectory] is true, creates a file in the temporary directory for sharing
  /// Otherwise, creates a file in the application documents directory
  Future<String> exportToFile(
    List<LocalRule>? rules, {
    bool useTemporaryDirectory = false,
  }) async {
    final jsonString = exportToJson(rules);
    final directory = useTemporaryDirectory
        ? await getTemporaryDirectory()
        : await getApplicationDocumentsDirectory();
    final formattedTimestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-')
        .substring(0, 19);
    final file = File('${directory.path}/LinkPure_$formattedTimestamp.json');
    await file.writeAsString(jsonString);
    return file.path;
  }

  /// Import rules from JSON string (plain array format only)
  Future<void> importFromJson(String jsonString, {bool merge = false}) async {
    try {
      final jsonData = jsonDecode(jsonString);

      // Only support plain array format
      if (jsonData is! List<dynamic>) {
        throw Exception('Invalid JSON format: expected array');
      }

      final importedRules = jsonData
          .map((e) => ExportedRule.fromJson(e as Map<String, dynamic>))
          .map((e) => ExportedRule.toLocalRule(e))
          .toList();

      if (merge) {
        // Merge mode: add new rules, skip existing IDs
        for (final rule in importedRules) {
          final exists = _rules.any((r) => r.rule.id == rule.rule.id);
          if (!exists) {
            _rules.add(rule);
          }
        }
      } else {
        // Replace mode: clear existing rules
        _rules = importedRules;
      }

      await _save();
    } catch (e) {
      throw Exception('Failed to import rules: $e');
    }
  }

  /// Import rules from file
  Future<void> importFromFile(String filePath, {bool merge = false}) async {
    final file = File(filePath);
    final jsonString = await file.readAsString();
    await importFromJson(jsonString, merge: merge);
  }

  /// Clear all rules
  Future<void> clearAll() async {
    _rules.clear();
    await _save();
  }
}

class ExportedRule {
  final String id;
  final String from;
  final String to;
  final bool enabled;

  ExportedRule({
    required this.id,
    required this.from,
    required this.to,
    required this.enabled,
  });

  static ExportedRule fromLocalRule(LocalRule rule) {
    // Only supports converting regexSubstitution type rules
    if (rule.rule.regexSubstitution == null) {
      throw ArgumentError(
        'Cannot export rule "${rule.rule.id}": only regexSubstitution rules can be exported',
      );
    }
    return ExportedRule(
      id: rule.rule.id,
      from: rule.rule.regexFilter,
      to: rule.rule.regexSubstitution!,
      enabled: rule.enabled,
    );
  }

  static LocalRule toLocalRule(ExportedRule rule) {
    // Imported rules are always converted to regexSubstitution type
    return LocalRule(
      rule: Rule(
        id: rule.id,
        regexFilter: rule.from,
        regexSubstitution: rule.to,
      ),
      enabled: rule.enabled,
    );
  }

  factory ExportedRule.fromJson(Map<String, dynamic> json) {
    return ExportedRule(
      id: json['id'] as String,
      from: json['from'] as String,
      to: json['to'] as String,
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'from': from, 'to': to, 'enabled': enabled};
  }
}
