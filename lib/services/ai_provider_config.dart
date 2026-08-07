class AiProviderConfig {
  static const defaultBackupBaseUrl = 'https://api.groq.com/openai/v1';
  static const defaultBackupModel = 'openai/gpt-oss-20b';

  final String backupApiKey;
  final String backupBaseUrl;
  final String backupModel;

  const AiProviderConfig({
    this.backupApiKey = '',
    this.backupBaseUrl = defaultBackupBaseUrl,
    this.backupModel = defaultBackupModel,
  });

  static AiProviderConfig _current = const AiProviderConfig();

  static AiProviderConfig get current => _current;

  static void update({
    required String backupApiKey,
    required String backupBaseUrl,
    required String backupModel,
  }) {
    _current = AiProviderConfig(
      backupApiKey: backupApiKey.trim(),
      backupBaseUrl: normalizeBaseUrl(backupBaseUrl),
      backupModel: backupModel.trim().isEmpty
          ? defaultBackupModel
          : backupModel.trim(),
    );
  }

  bool get hasBackup => backupApiKey.trim().isNotEmpty;

  Uri? get chatCompletionsUri {
    final normalized = normalizeBaseUrl(backupBaseUrl);
    final raw = normalized.endsWith('/chat/completions')
        ? normalized
        : '$normalized/chat/completions';
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    if (uri.scheme != 'https' && uri.scheme != 'http') return null;
    return uri;
  }

  static String normalizeBaseUrl(String value) {
    var result = value.trim();
    if (result.isEmpty) result = defaultBackupBaseUrl;
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }
}
