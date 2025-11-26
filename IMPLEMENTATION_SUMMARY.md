# LinkPure 规则配置管理器

## 🎉 功能完成清单

✅ **本地规则 CRUD 操作**
- 创建规则 (`newRule`)
- 读取规则 (`getLocalRules`)
- 更新规则 (`updateRule`)
- 删除规则 (`deleteRule`)

✅ **数据持久化**
- 使用 `shared_preferences` 存储配置
- 自动保存所有更改
- 支持应用重启后恢复数据

✅ **导入/导出功能**
- 导出为 JSON 字符串 (`exportToJson`)
- 导出到文件 (`exportToFile`)
- 从 JSON 导入 (`importFromJson`)
- 从文件导入 (`importFromFile`)
- 支持合并或替换模式

✅ **两种规则类型**
- URL 参数清理规则 (`removeParams`)
- 正则表达式重写规则 (`regexSubstitution`)

## 📁 文件结构

```
lib/
├── core/
│   └── rules_manager.dart          # 核心管理器实现
├── models/
│   └── rule.dart                   # 规则数据模型（已增强）
└── examples/
    └── rules_manager_example.dart  # 使用示例代码

test/
└── rules_manager_test.dart         # 单元测试（13个测试全部通过）

docs/
└── RULES_MANAGER.md                # 详细使用文档
```

## 🚀 快速开始

### 1. 初始化

```dart
final rulesManager = RulesManager();
await rulesManager.init();
```

### 2. 创建规则

```dart
// 参数移除规则
final rule1 = LocalRule(
  rule: Rule(
    id: 'remove-tracking',
    regexFilter: r'.*',
    removeParams: ['utm_source', 'utm_medium', 'fbclid'],
  ),
  enabled: true,
);
await rulesManager.localRules.newRule(rule1);

// URL 重写规则
final rule2 = LocalRule(
  rule: Rule(
    id: 'youtube-shorts',
    regexFilter: r'^https://youtube\.com/shorts/([^?]+)',
    regexSubstitution: r'https://youtube.com/watch?v=$1',
  ),
  enabled: true,
);
await rulesManager.localRules.newRule(rule2);
```

### 3. 导出配置

```dart
// 导出到文件
final filePath = await rulesManager.localRules.exportToFile(null);
print('已导出到: $filePath');

// 或导出为 JSON 字符串
final json = rulesManager.localRules.exportToJson(null);
```

### 4. 导入配置

```dart
// 从文件导入（替换现有规则）
await rulesManager.localRules.importFromFile(filePath, merge: false);

// 从 JSON 导入（合并到现有规则）
await rulesManager.localRules.importFromJson(jsonString, merge: true);
```

## 📊 导出格式示例

```json
{
  "version": "1.0",
  "exportDate": "2024-11-24T10:30:00.000Z",
  "rules": [
    {
      "id": "remove-tracking",
      "from": ".*",
      "to": "",
      "enabled": true,
      "removeParams": ["utm_source", "utm_medium", "fbclid"]
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

## 🔧 技术实现

### 核心类

- **RulesManager**: 主管理器，协调本地和共享规则
- **LocalRules**: 本地规则管理，处理 CRUD 和导入/导出
- **LocalRule**: 规则包装器，包含规则和启用状态
- **ExportedRule**: 导入/导出数据传输对象
- **Rule**: 规则定义（已增强 toJson 支持）

### 依赖包

```yaml
dependencies:
  shared_preferences: ^2.3.3   # 键值对存储
  path_provider: ^2.1.5        # 获取系统路径
```

## ✅ 测试覆盖

13个单元测试全部通过，涵盖：
- 初始化和基本 CRUD 操作
- 导入导出功能（JSON 和文件）
- 合并和替换模式
- 数据持久化
- 类型转换

运行测试：
```bash
flutter test test/rules_manager_test.dart
```

## 📚 更多信息

- 详细文档: `docs/RULES_MANAGER.md`
- 示例代码: `lib/examples/rules_manager_example.dart`
- 单元测试: `test/rules_manager_test.dart`

## 🎯 下一步

1. 在 UI 中集成规则管理器
2. 实现规则测试工具
3. 添加云端同步功能
4. 创建规则市场/社区共享

---

**状态**: ✅ 已完成并测试通过  
**版本**: 1.0.0  
**日期**: 2024-11-24
