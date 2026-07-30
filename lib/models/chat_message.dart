class ChatMessage {
  final String text;
  final bool isUser;
  final bool isLocalNotice;
  final DateTime createdAt;

  const ChatMessage({
    required this.text,
    required this.isUser,
    this.isLocalNotice = false,
    required this.createdAt,
  });

  String get sender => isUser ? 'Ти' : 'Iron Music 420 AI';

  Map<String, dynamic> toJson() => {
        'text': text,
        'isUser': isUser,
        'isLocalNotice': isLocalNotice,
        'createdAt': createdAt.toIso8601String(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      text: json['text']?.toString() ?? '',
      isUser: json['isUser'] == true,
      isLocalNotice: json['isLocalNotice'] == true,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}
