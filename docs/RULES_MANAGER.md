# 规则配置管理器使用指南

## 概述

LinkPure 的规则配置管理器提供了完整的规则管理功能，支持：
- ✅ 本地规则的 CRUD 操作
- ✅ 使用 SharedPreferences 持久化存储
- ✅ 导入/导出配置文件（JSON 格式）
- ✅ 合并或替换导入模式
- ✅ 支持 URL 参数清理和正则重写规则

## 核心组件

### 1. RulesManager
主要的规则管理器，负责协调本地规则和共享规则。

```dart
final rulesManager = RulesManager();
await rulesManager.init(); // 必须先初始化
```

### 2. LocalRules
管理本地自定义规则，提供完整的 CRUD 和导入/导出功能。

### 3. Rule
规则定义，支持两种类型：
- **参数移除规则**：使用 `removeParams` 移除指定的 URL 参数
- **正则重写规则**：使用 `regexFilter` 和 `regexSubstitution` 进行 URL 重写

### 4. LocalRule
本地规则包装器，包含规则本身和启用状态。

## 使用方法

### 初始化

```dart
final rulesManager = RulesManager();
await rulesManager.init();
```

### 创建规则

#### 创建参数移除规则

```dart
final rule = LocalRule(
  rule: Rule(
    id: 'remove-utm-params',
    regexFilter: r'.*',
    removeParams: ['utm_source', 'utm_medium', 'utm_campaign', 'fbclid'],
  ),
  enabled: true,
);

await rulesManager.localRules.newRule(rule);
```

#### 创建 URL 重写规则

```dart
final rule = LocalRule(
  rule: Rule(
    id: 'youtube-shorts-to-watch',
    regexFilter: r'^https://youtube\.com/shorts/([^?]+)',
    regexSubstitution: r'https://youtube.com/watch?v=$1',
  ),
  enabled: true,
);

await rulesManager.localRules.newRule(rule);
```

### 查询规则

```dart
// 获取所有本地规则
final localRules = rulesManager.localRules.getLocalRules();

// 获取所有启用的规则（包括共享规则和本地规则）
final enabledRules = await rulesManager.getEnabledRules();
```

### 更新规则

```dart
final updatedRule = LocalRule(
  rule: existingRule.rule,
  enabled: false, // 禁用规则
);

await rulesManager.localRules.updateRule('rule-id', updatedRule);
```

### 删除规则

```dart
await rulesManager.localRules.deleteRule('rule-id');
```

### 导出规则

#### 导出为 JSON 字符串

```dart
// 导出所有规则
final jsonString = rulesManager.localRules.exportToJson(null);

// 导出指定规则
final selectedRules = [rule1, rule2];
final jsonString = rulesManager.localRules.exportToJson(selectedRules);
```

#### 导出到文件

```dart
final filePath = await rulesManager.localRules.exportToFile(null);
print('规则已导出到: $filePath');
```

### 导入规则

#### 从 JSON 字符串导入

```dart
const jsonString = '''
{
  "version": "1.0",
  "exportDate": "2024-01-01T00:00:00.000Z",
  "rules": [
    {
      "id": "test-rule",
      "from": ".*",
      "to": "",
      "enabled": true
    }
  ]
}
''';

// 替换模式：清除现有规则后导入
await rulesManager.localRules.importFromJson(jsonString, merge: false);

// 合并模式：保留现有规则，添加新规则（跳过重复 ID）
await rulesManager.localRules.importFromJson(jsonString, merge: true);
```

#### 从文件导入

```dart
await rulesManager.localRules.importFromFile('/path/to/rules.json', merge: false);
```

### 清除所有规则

```dart
await rulesManager.localRules.clearAll();
```

## 导出 JSON 格式

导出的 JSON 文件格式如下：

```json
{
  "version": "1.0",
  "exportDate": "2024-11-24T10:30:00.000Z",
  "rules": [
    {
      "id": "remove-utm-params",
      "from": ".*",
      "to": "",
      "enabled": true
    },
    {
      "id": "youtube-shorts",
      "from": "^https://youtube\\.com/shorts/([^?]+)",
      "to": "https://youtube.com/watch?v=$1",
      "enabled": true
    }
  ]
}
```

### 字段说明

- `version`: 配置文件格式版本
- `exportDate`: 导出时间（ISO 8601 格式）
- `rules`: 规则数组
  - `id`: 规则唯一标识符
  - `from`: 正则表达式匹配模式
  - `to`: 重写目标（为空时表示使用参数移除）
  - `enabled`: 是否启用

## 数据持久化

规则配置使用 `shared_preferences` 包存储在设备本地：

- **存储键**: `local_rules`
- **数据格式**: JSON 字符串
- **自动保存**: 所有修改操作（增删改）后自动持久化

## 错误处理

```dart
try {
  await rulesManager.localRules.importFromFile(filePath);
} catch (e) {
  print('导入失败: $e');
  // 处理错误
}
```

## 最佳实践

1. **始终初始化**: 在使用 RulesManager 前调用 `init()` 方法
2. **唯一 ID**: 确保每个规则有唯一的 ID
3. **正则测试**: 创建正则重写规则前，先测试正则表达式
4. **合并导入**: 使用 `merge: true` 避免覆盖现有规则
5. **备份**: 定期导出规则配置作为备份

## 完整示例

参考 `lib/examples/rules_manager_example.dart` 文件查看完整的使用示例。

## 技术栈

- **Flutter**: 跨平台 UI 框架
- **shared_preferences**: 键值对持久化存储
- **path_provider**: 获取系统目录路径
- **dart:convert**: JSON 序列化/反序列化

## 未来扩展

- [ ] 支持云端同步
- [ ] 规则市场/社区共享
- [ ] 规则测试工具
- [ ] 批量导入/导出
- [ ] 规则优先级排序
