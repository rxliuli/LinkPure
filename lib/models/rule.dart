class TestCase {
  final String from;
  final String to;

  TestCase({required this.from, required this.to});

  factory TestCase.fromJson(Map<String, dynamic> json) {
    return TestCase(from: json['from'] as String, to: json['to'] as String);
  }

  Map<String, dynamic> toJson() {
    return {
      'from': from,
      'to': to,
    };
  }
}

class Rule {
  final String id;
  final String regexFilter;
  final String? regexSubstitution;
  final List<String>? removeParams;
  final List<TestCase>? test;

  Rule({
    required this.id,
    required this.regexFilter,
    this.regexSubstitution,
    this.removeParams,
    this.test,
  }) {
    if (regexSubstitution != null && removeParams != null) {
      throw ArgumentError(
        'A rule cannot have both regexSubstitution and removeParams defined.',
      );
    }
    if (regexSubstitution == null && removeParams == null) {
      throw ArgumentError(
        'A rule must have either regexSubstitution or removeParams defined.',
      );
    }
  }

  factory Rule.fromJson(Map<String, dynamic> json) {
    return Rule(
      id: json['id'] as String,
      regexFilter: json['regexFilter'] as String,
      regexSubstitution: json['regexSubstitution'] as String?,
      removeParams: (json['removeParams'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      test: (json['test'] as List<dynamic>?)
          ?.map((e) => TestCase.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'regexFilter': regexFilter,
      if (regexSubstitution != null) 'regexSubstitution': regexSubstitution,
      if (removeParams != null) 'removeParams': removeParams,
      if (test != null) 'test': test!.map((e) => e.toJson()).toList(),
    };
  }
}

class RuleSet {
  final String name;
  final String description;
  final List<Rule> rules;

  RuleSet({required this.name, required this.description, required this.rules});

  factory RuleSet.fromJson(Map<String, dynamic> json) {
    return RuleSet(
      name: json['name'] as String,
      description: json['description'] as String,
      rules: (json['rules'] as List<dynamic>)
          .map((e) => Rule.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'rules': rules.map((e) => e.toJson()).toList(),
    };
  }
}
