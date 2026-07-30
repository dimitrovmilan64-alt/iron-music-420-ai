class CustomAutomation {
  final String id;
  final String name;
  final String voicePhrase;
  final List<String> actions;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CustomAutomation({
    required this.id,
    required this.name,
    required this.voicePhrase,
    required this.actions,
    required this.createdAt,
    required this.updatedAt,
  });

  CustomAutomation copyWith({
    String? name,
    String? voicePhrase,
    List<String>? actions,
    DateTime? updatedAt,
  }) {
    return CustomAutomation(
      id: id,
      name: name ?? this.name,
      voicePhrase: voicePhrase ?? this.voicePhrase,
      actions: actions ?? this.actions,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'voicePhrase': voicePhrase,
        'actions': actions,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory CustomAutomation.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return CustomAutomation(
      id: (json['id'] as String?)?.trim().isNotEmpty == true
          ? json['id'] as String
          : now.microsecondsSinceEpoch.toString(),
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? json['name'] as String
          : 'Моя автоматизация',
      voicePhrase: (json['voicePhrase'] as String?) ?? '',
      actions: (json['actions'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .where((item) => item.trim().isNotEmpty)
          .toList(growable: false),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? now,
    );
  }
}

class AutomationHistoryEntry {
  final String id;
  final String title;
  final bool success;
  final String message;
  final DateTime executedAt;

  const AutomationHistoryEntry({
    required this.id,
    required this.title,
    required this.success,
    required this.message,
    required this.executedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'success': success,
        'message': message,
        'executedAt': executedAt.toIso8601String(),
      };

  factory AutomationHistoryEntry.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return AutomationHistoryEntry(
      id: (json['id'] as String?) ?? now.microsecondsSinceEpoch.toString(),
      title: (json['title'] as String?) ?? 'Автоматизация',
      success: json['success'] as bool? ?? false,
      message: (json['message'] as String?) ?? '',
      executedAt: DateTime.tryParse(json['executedAt'] as String? ?? '') ?? now,
    );
  }
}
