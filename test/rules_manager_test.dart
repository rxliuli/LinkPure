import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:link_pure/core/url_cleaner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:link_pure/core/rules_manager.dart';
import 'package:link_pure/models/rule.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RulesManager Tests', () {
    late RulesManager rulesManager;

    setUp(() async {
      // Clear SharedPreferences
      SharedPreferences.setMockInitialValues({});
      rulesManager = RulesManager();
      await rulesManager.init();
    });

    tearDown(() async {
      // Cleanup
      await rulesManager.localRules.clearAll();
    });

    test('should have no local rules after initialization', () {
      expect(rulesManager.localRules.getLocalRules().length, 0);
    });

    test('should be able to create new rule', () async {
      final rule = LocalRule(
        rule: Rule(
          id: 'test-rule',
          regexFilter: r'.*',
          removeParams: ['utm_source'],
        ),
        enabled: true,
      );

      await rulesManager.localRules.newRule(rule);
      expect(rulesManager.localRules.getLocalRules().length, 1);
      expect(
        rulesManager.localRules.getLocalRules().first.rule.id,
        'test-rule',
      );
    });

    test('should be able to update rule', () async {
      final rule = LocalRule(
        rule: Rule(
          id: 'test-rule',
          regexFilter: r'.*',
          removeParams: ['utm_source'],
        ),
        enabled: true,
      );

      await rulesManager.localRules.newRule(rule);

      final updatedRule = LocalRule(rule: rule.rule, enabled: false);

      await rulesManager.localRules.updateRule('test-rule', updatedRule);

      final rules = rulesManager.localRules.getLocalRules();
      expect(rules.first.enabled, false);
    });

    test('should be able to delete rule', () async {
      final rule = LocalRule(
        rule: Rule(
          id: 'test-rule',
          regexFilter: r'.*',
          removeParams: ['utm_source'],
        ),
        enabled: true,
      );

      await rulesManager.localRules.newRule(rule);
      expect(rulesManager.localRules.getLocalRules().length, 1);

      await rulesManager.localRules.deleteRule('test-rule');
      expect(rulesManager.localRules.getLocalRules().length, 0);
    });

    test('should be able to export rules to JSON', () async {
      final rule = LocalRule(
        rule: Rule(
          id: 'test-rule',
          regexFilter: r'.*',
          regexSubstitution: r'https://cleaned.com',
        ),
        enabled: true,
      );

      await rulesManager.localRules.newRule(rule);

      final json = rulesManager.localRules.exportToJson(null);
      expect(json.contains('test-rule'), true);
      // Should not contain wrapper fields anymore
      expect(json.contains('version'), false);
      expect(json.contains('exportDate'), false);
    });

    test('should export rules as plain array format', () async {
      final rule1 = LocalRule(
        rule: Rule(
          id: 'rule-1',
          regexFilter: r'^https://example\.com',
          regexSubstitution: r'https://example.org',
        ),
        enabled: true,
      );
      final rule2 = LocalRule(
        rule: Rule(
          id: 'rule-2',
          regexFilter: r'^https://test\.com',
          regexSubstitution: r'https://test.org',
        ),
        enabled: false,
      );

      await rulesManager.localRules.newRule(rule1);
      await rulesManager.localRules.newRule(rule2);

      final jsonString = rulesManager.localRules.exportToJson(null);
      final decoded = jsonDecode(jsonString);

      // Should be a plain array, not an object
      expect(decoded, isA<List<dynamic>>());
      expect(decoded.length, 2);

      // Verify first rule
      expect(decoded[0]['id'], 'rule-1');
      expect(decoded[0]['from'], r'^https://example\.com');
      expect(decoded[0]['to'], r'https://example.org');
      expect(decoded[0]['enabled'], true);

      // Verify second rule
      expect(decoded[1]['id'], 'rule-2');
      expect(decoded[1]['from'], r'^https://test\.com');
      expect(decoded[1]['to'], r'https://test.org');
      expect(decoded[1]['enabled'], false);
    });

    test('should be able to import plain array format exported JSON', () async {
      // Export rules
      final rule1 = LocalRule(
        rule: Rule(
          id: 'exported-rule-1',
          regexFilter: r'^https://example\.com',
          regexSubstitution: r'https://example.org',
        ),
        enabled: true,
      );
      final rule2 = LocalRule(
        rule: Rule(
          id: 'exported-rule-2',
          regexFilter: r'^https://test\.com',
          regexSubstitution: r'https://test.org',
        ),
        enabled: false,
      );

      await rulesManager.localRules.newRule(rule1);
      await rulesManager.localRules.newRule(rule2);

      final exportedJson = rulesManager.localRules.exportToJson(null);

      // Clear all rules
      await rulesManager.localRules.clearAll();
      expect(rulesManager.localRules.getLocalRules().length, 0);

      // Import the exported JSON
      await rulesManager.localRules.importFromJson(exportedJson, merge: false);

      final importedRules = rulesManager.localRules.getLocalRules();
      expect(importedRules.length, 2);
      expect(importedRules[0].rule.id, 'exported-rule-1');
      expect(importedRules[0].rule.regexFilter, r'^https://example\.com');
      expect(importedRules[0].rule.regexSubstitution, r'https://example.org');
      expect(importedRules[0].enabled, true);
      expect(importedRules[1].rule.id, 'exported-rule-2');
      expect(importedRules[1].enabled, false);
    });

    test('should be able to import rules from JSON (replace mode)', () async {
      const jsonString = '''
      [
        {
          "id": "imported-rule",
          "from": ".*",
          "to": "https://example.com",
          "enabled": true
        }
      ]
      ''';

      await rulesManager.localRules.importFromJson(jsonString, merge: false);

      final rules = rulesManager.localRules.getLocalRules();
      expect(rules.length, 1);
      expect(rules.first.rule.id, 'imported-rule');
      expect(rules.first.rule.regexSubstitution, 'https://example.com');
    });

    test('should be able to import rules from JSON (merge mode)', () async {
      // Add an existing rule first
      final existingRule = LocalRule(
        rule: Rule(
          id: 'existing-rule',
          regexFilter: r'.*',
          removeParams: ['utm_source'],
        ),
        enabled: true,
      );
      await rulesManager.localRules.newRule(existingRule);

      // Import new rule
      const jsonString = '''
      [
        {
          "id": "imported-rule",
          "from": ".*",
          "to": "https://imported.com",
          "enabled": true
        }
      ]
      ''';

      await rulesManager.localRules.importFromJson(jsonString, merge: true);

      final rules = rulesManager.localRules.getLocalRules();
      expect(rules.length, 2);
      expect(rules.any((r) => r.rule.id == 'existing-rule'), true);
      expect(rules.any((r) => r.rule.id == 'imported-rule'), true);
    });

    test('should skip duplicate IDs when importing in merge mode', () async {
      final existingRule = LocalRule(
        rule: Rule(
          id: 'same-id',
          regexFilter: r'.*',
          removeParams: ['utm_source'],
        ),
        enabled: true,
      );
      await rulesManager.localRules.newRule(existingRule);

      const jsonString = '''
      [
        {
          "id": "same-id",
          "from": ".*different.*",
          "to": "https://different.com",
          "enabled": false
        }
      ]
      ''';

      await rulesManager.localRules.importFromJson(jsonString, merge: true);

      final rules = rulesManager.localRules.getLocalRules();
      expect(rules.length, 1);
      // Should keep the original rule
      expect(rules.first.rule.regexFilter, r'.*');
    });

    test('should reject wrapper format when importing', () async {
      const jsonString = '''
      {
        "version": "1.0",
        "exportDate": "2024-01-01T00:00:00.000Z",
        "rules": [
          {
            "id": "test-rule",
            "from": ".*",
            "to": "https://example.com",
            "enabled": true
          }
        ]
      }
      ''';

      expect(
        () async => await rulesManager.localRules.importFromJson(jsonString),
        throwsException,
      );
    });

    test('should only export regexSubstitution type rules', () async {
      final rewriteRule = LocalRule(
        rule: Rule(
          id: 'rewrite-rule',
          regexFilter: r'.*',
          regexSubstitution: r'https://rewritten.com',
        ),
        enabled: true,
      );
      final removeParamsRule = LocalRule(
        rule: Rule(
          id: 'remove-params-rule',
          regexFilter: r'.*',
          removeParams: ['utm_source'],
        ),
        enabled: true,
      );

      await rulesManager.localRules.newRule(rewriteRule);
      await rulesManager.localRules.newRule(removeParamsRule);

      final json = rulesManager.localRules.exportToJson(null);
      expect(json.contains('rewrite-rule'), true);
      expect(json.contains('remove-params-rule'), false);
    });

    test('should be able to clear all rules', () async {
      final rule1 = LocalRule(
        rule: Rule(
          id: 'rule-1',
          regexFilter: r'.*',
          removeParams: ['utm_source'],
        ),
        enabled: true,
      );
      final rule2 = LocalRule(
        rule: Rule(id: 'rule-2', regexFilter: r'.*', removeParams: ['fbclid']),
        enabled: true,
      );

      await rulesManager.localRules.newRule(rule1);
      await rulesManager.localRules.newRule(rule2);
      expect(rulesManager.localRules.getLocalRules().length, 2);

      await rulesManager.localRules.clearAll();
      expect(rulesManager.localRules.getLocalRules().length, 0);
    });

    test('rules should persist to SharedPreferences', () async {
      final rule = LocalRule(
        rule: Rule(
          id: 'test-rule',
          regexFilter: r'.*',
          removeParams: ['utm_source'],
        ),
        enabled: true,
      );

      await rulesManager.localRules.newRule(rule);

      // Create a new RulesManager instance to simulate restart
      final newRulesManager = RulesManager();
      await newRulesManager.init();

      final rules = newRulesManager.localRules.getLocalRules();
      expect(rules.length, 1);
      expect(rules.first.rule.id, 'test-rule');
    });
  });

  group('ExportedRule Tests', () {
    test('should be able to convert from LocalRule to ExportedRule', () {
      final localRule = LocalRule(
        rule: Rule(
          id: 'test-rule',
          regexFilter: r'^https://example\.com',
          regexSubstitution: r'https://example.org',
        ),
        enabled: true,
      );

      final exported = ExportedRule.fromLocalRule(localRule);

      expect(exported.id, 'test-rule');
      expect(exported.from, r'^https://example\.com');
      expect(exported.to, r'https://example.org');
      expect(exported.enabled, true);
    });

    test('should be able to convert from ExportedRule to LocalRule', () {
      final exported = ExportedRule(
        id: 'test-rule',
        from: r'^https://example\.com',
        to: r'https://example.org',
        enabled: true,
      );

      final localRule = ExportedRule.toLocalRule(exported);

      expect(localRule.rule.id, 'test-rule');
      expect(localRule.rule.regexFilter, r'^https://example\.com');
      expect(localRule.rule.regexSubstitution, r'https://example.org');
      expect(localRule.enabled, true);
    });

    test('creating ExportedRule from removeParams rule should throw exception', () {
      final localRule = LocalRule(
        rule: Rule(
          id: 'test-rule',
          regexFilter: r'.*',
          removeParams: ['utm_source'],
        ),
        enabled: true,
      );

      expect(() => ExportedRule.fromLocalRule(localRule), throwsArgumentError);
    });
  });

  group("Real Tests", () {
    setUp(() async {
      // Clear SharedPreferences
      SharedPreferences.setMockInitialValues({});
    });

    test("clean twitter share link", () async {
      final rulesManager = RulesManager();
      await rulesManager.init();
      final rules = await rulesManager.getEnabledRules();
      final cleaner = UrlCleaner(rules: rules);
      final inputUrl =
          "https://x.com/viditchess/status/1992583484259643817?s=20";
      final result = await cleaner.check(inputUrl);
      expect(result.status, CheckStatus.matched);
      expect(result.url, "https://x.com/viditchess/status/1992583484259643817");
    });
    test("clean reddit share link", () async {
      final rulesManager = RulesManager();
      await rulesManager.init();
      final rules = await rulesManager.getEnabledRules();
      final cleaner = UrlCleaner(rules: rules);
      final inputUrl =
          "https://www.reddit.com/r/amphibia/comments/1meq85j/hi_everyone_big_fan_of_amphibia_im_not_feeling/?utm_source=share&utm_medium=mweb3x&utm_name=mweb3xcss&utm_term=1&utm_content=share_button";
      final result = await cleaner.check(inputUrl);
      expect(result.status, CheckStatus.matched);
      expect(
        result.url,
        "https://www.reddit.com/r/amphibia/comments/1meq85j/hi_everyone_big_fan_of_amphibia_im_not_feeling/",
      );
    });
    test("should not clean non-share link", () async {
      // https://youtu.be/(.*)\?
      final rulesManager = RulesManager();
      final rules = await rulesManager.getEnabledRules();
      final cleaner = UrlCleaner(rules: rules);
      final inputUrl = "https://youtu.be/(.*)\\?";
      final result = await cleaner.check(inputUrl);
      expect(result.status, CheckStatus.notMatched);
      expect(result.url, "");
    });
    test("should not encodeURIComponent URL parameters", () async {
      final rulesManager = RulesManager();
      await rulesManager.init();
      final rules = await rulesManager.getEnabledRules();
      final cleaner = UrlCleaner(rules: rules);
      final inputUrl = "https://www.youtube.com/watch?v=\$1";
      final result = await cleaner.check(inputUrl);
      expect(result.status, CheckStatus.notMatched);
      expect(result.url, "");
    });
  });
}
