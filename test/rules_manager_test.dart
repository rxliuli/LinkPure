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
      // 清除 SharedPreferences
      SharedPreferences.setMockInitialValues({});
      rulesManager = RulesManager();
      await rulesManager.init();
    });

    tearDown(() async {
      // 清理
      await rulesManager.localRules.clearAll();
    });

    test('初始化后应该没有本地规则', () {
      expect(rulesManager.localRules.getLocalRules().length, 0);
    });

    test('应该能够创建新规则', () async {
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

    test('应该能够更新规则', () async {
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

    test('应该能够删除规则', () async {
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

    test('应该能够导出规则为 JSON', () async {
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
      expect(json.contains('version'), true);
    });

    test('应该能够从 JSON 导入规则（替换模式）', () async {
      const jsonString = '''
      {
        "version": "1.0",
        "exportDate": "2024-01-01T00:00:00.000Z",
        "rules": [
          {
            "id": "imported-rule",
            "from": ".*",
            "to": "https://example.com",
            "enabled": true
          }
        ]
      }
      ''';

      await rulesManager.localRules.importFromJson(jsonString, merge: false);

      final rules = rulesManager.localRules.getLocalRules();
      expect(rules.length, 1);
      expect(rules.first.rule.id, 'imported-rule');
      expect(rules.first.rule.regexSubstitution, 'https://example.com');
    });

    test('应该能够从 JSON 导入规则（合并模式）', () async {
      // 先添加一个规则
      final existingRule = LocalRule(
        rule: Rule(
          id: 'existing-rule',
          regexFilter: r'.*',
          removeParams: ['utm_source'],
        ),
        enabled: true,
      );
      await rulesManager.localRules.newRule(existingRule);

      // 导入新规则
      const jsonString = '''
      {
        "version": "1.0",
        "exportDate": "2024-01-01T00:00:00.000Z",
        "rules": [
          {
            "id": "imported-rule",
            "from": ".*",
            "to": "https://imported.com",
            "enabled": true
          }
        ]
      }
      ''';

      await rulesManager.localRules.importFromJson(jsonString, merge: true);

      final rules = rulesManager.localRules.getLocalRules();
      expect(rules.length, 2);
      expect(rules.any((r) => r.rule.id == 'existing-rule'), true);
      expect(rules.any((r) => r.rule.id == 'imported-rule'), true);
    });

    test('合并模式导入时应该跳过重复的 ID', () async {
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
      {
        "version": "1.0",
        "exportDate": "2024-01-01T00:00:00.000Z",
        "rules": [
          {
            "id": "same-id",
            "from": ".*different.*",
            "to": "https://different.com",
            "enabled": false
          }
        ]
      }
      ''';

      await rulesManager.localRules.importFromJson(jsonString, merge: true);

      final rules = rulesManager.localRules.getLocalRules();
      expect(rules.length, 1);
      // 应该保留原始规则
      expect(rules.first.rule.regexFilter, r'.*');
    });

    test('应该只导出 regexSubstitution 类型的规则', () async {
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

    test('应该能够清除所有规则', () async {
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

    test('规则应该持久化到 SharedPreferences', () async {
      final rule = LocalRule(
        rule: Rule(
          id: 'test-rule',
          regexFilter: r'.*',
          removeParams: ['utm_source'],
        ),
        enabled: true,
      );

      await rulesManager.localRules.newRule(rule);

      // 创建新的 RulesManager 实例来模拟重启
      final newRulesManager = RulesManager();
      await newRulesManager.init();

      final rules = newRulesManager.localRules.getLocalRules();
      expect(rules.length, 1);
      expect(rules.first.rule.id, 'test-rule');
    });
  });

  group('ExportedRule Tests', () {
    test('应该能够从 LocalRule 转换为 ExportedRule', () {
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

    test('应该能够从 ExportedRule 转换为 LocalRule', () {
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

    test('从 removeParams 规则创建 ExportedRule 应该抛出异常', () {
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
      // 清除 SharedPreferences
      SharedPreferences.setMockInitialValues({});
    });

    test("清理 twitter 分享链接", () async {
      final rulesManager = RulesManager();
      await rulesManager.init();
      final rules = await rulesManager.getEnabledRules();
      final cleaner = UrlCleaner(rules: rules);
      final inputUrl =
          "https://x.com/viditchess/status/1992583484259643817?s=20";
      final result = cleaner.check(inputUrl);
      expect(result.status, CheckStatus.matched);
      expect(result.url, "https://x.com/viditchess/status/1992583484259643817");
    });
    test("清理 reddit 分享链接", () async {
      final rulesManager = RulesManager();
      await rulesManager.init();
      final rules = await rulesManager.getEnabledRules();
      final cleaner = UrlCleaner(rules: rules);
      final inputUrl =
          "https://www.reddit.com/r/amphibia/comments/1meq85j/hi_everyone_big_fan_of_amphibia_im_not_feeling/?utm_source=share&utm_medium=mweb3x&utm_name=mweb3xcss&utm_term=1&utm_content=share_button";
      final result = cleaner.check(inputUrl);
      expect(result.status, CheckStatus.matched);
      expect(
        result.url,
        "https://www.reddit.com/r/amphibia/comments/1meq85j/hi_everyone_big_fan_of_amphibia_im_not_feeling/",
      );
    });
    test("不应该清理非分享链接", () async {
      // https://youtu.be/(.*)\?
      final rulesManager = RulesManager();
      final rules = await rulesManager.getEnabledRules();
      final cleaner = UrlCleaner(rules: rules);
      final inputUrl = "https://youtu.be/(.*)\\?";
      final result = cleaner.check(inputUrl);
      expect(result.status, CheckStatus.notMatched);
      expect(result.url, "");
    });
    test("不应该将 URL 参数 encodeURIComponent", () async {
      final rulesManager = RulesManager();
      await rulesManager.init();
      final rules = await rulesManager.getEnabledRules();
      final cleaner = UrlCleaner(rules: rules);
      final inputUrl = "https://www.youtube.com/watch?v=\$1";
      final result = cleaner.check(inputUrl);
      expect(result.status, CheckStatus.notMatched);
      expect(result.url, "");
    });
  });
}
