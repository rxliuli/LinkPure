# LinkPure 规则配置管理器 - 快速参考

## API 参考

### RulesManager

```dart
final rulesManager = RulesManager();

// 初始化（必须）
await rulesManager.init();

// 获取所有启用的规则（本地 + 共享）
List<Rule> enabledRules = await rulesManager.getEnabledRules();

// 访问本地规则管理器
LocalRules localRules = rulesManager.localRules;
```

### LocalRules

```dart
// 查询
List<LocalRule> getLocalRules()

// 创建
await newRule(LocalRule rule)

// 更新
await updateRule(String ruleId, LocalRule updatedRule)

// 删除
await deleteRule(String ruleId)

// 导出
String exportToJson(List<LocalRule>? rules)
await String exportToFile(List<LocalRule>? rules)

// 导入
await importFromJson(String jsonString, {bool merge = false})
await importFromFile(String filePath, {bool merge = false})

// 清空
await clearAll()
```

### 规则类型

#### 1. 参数移除规则

```dart
Rule(
  id: 'unique-id',
  regexFilter: r'.*',  // 匹配所有 URL
  removeParams: ['utm_source', 'utm_medium', 'fbclid'],
)
```

#### 2. URL 重写规则

```dart
Rule(
  id: 'unique-id',
  regexFilter: r'^https://old\.com/(.+)',  // 匹配模式
  regexSubstitution: r'https://new.com/$1',  // 替换目标
)
```

## 常见场景

### 移除跟踪参数

```dart
final rule = LocalRule(
  rule: Rule(
    id: 'clean-tracking',
    regexFilter: r'.*',
    removeParams: [
      'utm_source', 'utm_medium', 'utm_campaign',
      'fbclid', 'gclid', 'msclkid'
    ],
  ),
  enabled: true,
);
await rulesManager.localRules.newRule(rule);
```

### YouTube Shorts 转换

```dart
final rule = LocalRule(
  rule: Rule(
    id: 'youtube-shorts',
    regexFilter: r'^https://(www\.)?youtube\.com/shorts/([^?]+)',
    regexSubstitution: r'https://youtube.com/watch?v=$2',
  ),
  enabled: true,
);
await rulesManager.localRules.newRule(rule);
```

### Twitter/X URL 清理

```dart
final rule = LocalRule(
  rule: Rule(
    id: 'twitter-clean',
    regexFilter: r'^https://(twitter|x)\.com/(.+)',
    removeParams: ['s', 't', 'ref_src', 'ref_url'],
  ),
  enabled: true,
);
await rulesManager.localRules.newRule(rule);
```

### Amazon 产品链接简化

```dart
final rule = LocalRule(
  rule: Rule(
    id: 'amazon-clean',
    regexFilter: r'^https://www\.amazon\..+/dp/([A-Z0-9]+)',
    regexSubstitution: r'https://amazon.com/dp/$1',
  ),
  enabled: true,
);
await rulesManager.localRules.newRule(rule);
```

## 导入/导出工作流

### 备份配置

```dart
// 导出所有规则到文件
final backupPath = await rulesManager.localRules.exportToFile(null);
print('配置已备份到: $backupPath');
```

### 恢复配置

```dart
// 从备份恢复（替换现有规则）
await rulesManager.localRules.importFromFile(backupPath, merge: false);
```

### 分享规则

```dart
// 导出特定规则
final rules = rulesManager.localRules.getLocalRules();
final selectedRules = rules.where((r) => r.rule.id.startsWith('social-')).toList();
final json = rulesManager.localRules.exportToJson(selectedRules);

// 分享 JSON 字符串...
```

### 导入社区规则

```dart
// 合并导入（保留现有规则）
await rulesManager.localRules.importFromJson(communityRulesJson, merge: true);
```

## 错误处理

```dart
try {
  await rulesManager.localRules.importFromFile(filePath);
  print('导入成功');
} catch (e) {
  print('导入失败: $e');
  // 显示错误提示给用户
}
```

## 性能建议

1. **初始化一次**: 在应用启动时调用 `init()` 一次
2. **批量操作**: 使用导入功能而非多次调用 `newRule()`
3. **定期清理**: 删除不再使用的规则
4. **测试正则**: 创建前验证正则表达式是否有效

## 存储位置

- **数据**: SharedPreferences (`local_rules` 键)
- **导出文件**: 应用文档目录 (`getApplicationDocumentsDirectory()`)
- **文件命名**: `link_pure_rules_<timestamp>.json`

## 限制

- Rule ID 必须唯一
- 规则必须包含 `regexSubstitution` 或 `removeParams` 之一（不能同时存在）
- `regexFilter` 必须是有效的正则表达式
- 导入时跳过重复 ID（合并模式）

## 调试

```dart
// 查看所有规则
final rules = rulesManager.localRules.getLocalRules();
for (final rule in rules) {
  print('${rule.rule.id}: ${rule.enabled ? "✓" : "✗"}');
}

// 查看规则详情
final json = rulesManager.localRules.exportToJson(null);
print(json);  // 查看 JSON 格式
```
