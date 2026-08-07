import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/automation_models.dart';
import '../models/chat_message.dart';
import '../models/song_project.dart';
import 'ai_provider_config.dart';

class LocalStore extends ChangeNotifier {
  static const _apiKeyKey = 'gemini_api_key';
  static const _backupApiKeyKey = 'backup_api_key';
  static const _backupBaseUrlKey = 'backup_base_url';
  static const _backupModelKey = 'backup_model';
  static const _voiceRepliesKey = 'voice_replies_enabled';
  static const _ttsRateKey = 'tts_rate_v152';
  static const _ttsPitchKey = 'tts_pitch_v152';
  static const _ttsVoiceNameKey = 'tts_voice_name_v152';
  static const _ttsVoiceLocaleKey = 'tts_voice_locale_v152';
  static const _chatHistoryKey = 'chat_history_v15';
  static const _rapDraftKey = 'rap_studio_draft';
  static const _rapResultKey = 'rap_studio_result';
  static const _songProjectsKey = 'song_projects_v20';
  static const _activeSongIdKey = 'active_song_id_v21';
  static const _favoriteAutomationIdsKey = 'favorite_automation_ids_v251';
  static const _customAutomationsKey = 'custom_automations_v251';
  static const _automationHistoryKey = 'automation_history_v251';

  late SharedPreferences _preferences;
  String _apiKey = '';
  String _backupApiKey = '';
  String _backupBaseUrl = AiProviderConfig.defaultBackupBaseUrl;
  String _backupModel = AiProviderConfig.defaultBackupModel;
  bool _voiceRepliesEnabled = true;
  double _ttsRate = 0.44;
  double _ttsPitch = 0.92;
  String _ttsVoiceName = '';
  String _ttsVoiceLocale = '';
  List<ChatMessage> _chatHistory = const [];
  String _rapDraft = '';
  String _rapResult = '';
  List<SongProject> _songProjects = const [];
  String _activeSongId = '';
  int _studioRevision = 0;
  Set<String> _favoriteAutomationIds = <String>{};
  List<CustomAutomation> _customAutomations = const [];
  List<AutomationHistoryEntry> _automationHistory = const [];

  Future<void> initialize() async {
    _preferences = await SharedPreferences.getInstance();
    _apiKey = _preferences.getString(_apiKeyKey) ?? '';
    _backupApiKey = _preferences.getString(_backupApiKeyKey) ?? '';
    _backupBaseUrl = AiProviderConfig.normalizeBaseUrl(
      _preferences.getString(_backupBaseUrlKey) ??
          AiProviderConfig.defaultBackupBaseUrl,
    );
    _backupModel = (_preferences.getString(_backupModelKey) ??
            AiProviderConfig.defaultBackupModel)
        .trim();
    if (_backupModel.isEmpty) {
      _backupModel = AiProviderConfig.defaultBackupModel;
    }
    _voiceRepliesEnabled = _preferences.getBool(_voiceRepliesKey) ?? true;
    _ttsRate = _preferences.getDouble(_ttsRateKey) ?? 0.44;
    _ttsPitch = _preferences.getDouble(_ttsPitchKey) ?? 0.92;
    _ttsVoiceName = _preferences.getString(_ttsVoiceNameKey) ?? '';
    _ttsVoiceLocale = _preferences.getString(_ttsVoiceLocaleKey) ?? '';
    _rapDraft = _preferences.getString(_rapDraftKey) ?? '';
    _rapResult = _preferences.getString(_rapResultKey) ?? '';
    _activeSongId = _preferences.getString(_activeSongIdKey) ?? '';
    _favoriteAutomationIds = (_preferences
                .getStringList(_favoriteAutomationIdsKey) ??
            const <String>[])
        .where((item) => item.trim().isNotEmpty)
        .toSet();

    final rawHistory = _preferences.getString(_chatHistoryKey);
    if (rawHistory != null && rawHistory.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawHistory) as List<dynamic>;
        _chatHistory = decoded
            .whereType<Map>()
            .map(
              (item) => ChatMessage.fromJson(
                Map<String, dynamic>.from(item),
              ),
            )
            .where((message) => message.text.trim().isNotEmpty)
            .toList(growable: false);
      } catch (_) {
        _chatHistory = const [];
      }
    }

    final rawProjects = _preferences.getString(_songProjectsKey);
    if (rawProjects != null && rawProjects.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawProjects) as List<dynamic>;
        _songProjects = decoded
            .whereType<Map>()
            .map(
              (item) => SongProject.fromJson(
                Map<String, dynamic>.from(item),
              ),
            )
            .toList(growable: false)
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      } catch (_) {
        _songProjects = const [];
      }
    }

    final rawCustomAutomations = _preferences.getString(_customAutomationsKey);
    if (rawCustomAutomations != null && rawCustomAutomations.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawCustomAutomations) as List<dynamic>;
        _customAutomations = decoded
            .whereType<Map>()
            .map(
              (item) => CustomAutomation.fromJson(
                Map<String, dynamic>.from(item),
              ),
            )
            .where((item) => item.actions.isNotEmpty)
            .toList(growable: false)
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      } catch (_) {
        _customAutomations = const [];
      }
    }

    final rawAutomationHistory = _preferences.getString(_automationHistoryKey);
    if (rawAutomationHistory != null && rawAutomationHistory.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawAutomationHistory) as List<dynamic>;
        _automationHistory = decoded
            .whereType<Map>()
            .map(
              (item) => AutomationHistoryEntry.fromJson(
                Map<String, dynamic>.from(item),
              ),
            )
            .toList(growable: false)
          ..sort((a, b) => b.executedAt.compareTo(a.executedAt));
      } catch (_) {
        _automationHistory = const [];
      }
    }

    if (_activeSongId.isNotEmpty &&
        !_songProjects.any((song) => song.id == _activeSongId)) {
      _activeSongId = '';
      await _preferences.remove(_activeSongIdKey);
    }

    _syncAiProviderConfig();
  }

  String get apiKey => _apiKey;
  bool get hasApiKey => _apiKey.trim().isNotEmpty;
  String get backupApiKey => _backupApiKey;
  String get backupBaseUrl => _backupBaseUrl;
  String get backupModel => _backupModel;
  bool get hasBackupProvider => _backupApiKey.trim().isNotEmpty;
  bool get hasAnyAiProvider => hasApiKey || hasBackupProvider;
  bool get voiceRepliesEnabled => _voiceRepliesEnabled;
  double get ttsRate => _ttsRate;
  double get ttsPitch => _ttsPitch;
  String get ttsVoiceName => _ttsVoiceName;
  String get ttsVoiceLocale => _ttsVoiceLocale;
  List<ChatMessage> get chatHistory => List.unmodifiable(_chatHistory);
  String get rapDraft => _rapDraft;
  String get rapResult => _rapResult;
  List<SongProject> get songProjects => List.unmodifiable(_songProjects);
  String get activeSongId => _activeSongId;
  int get studioRevision => _studioRevision;
  Set<String> get favoriteAutomationIds =>
      Set.unmodifiable(_favoriteAutomationIds);
  List<CustomAutomation> get customAutomations =>
      List.unmodifiable(_customAutomations);
  List<AutomationHistoryEntry> get automationHistory =>
      List.unmodifiable(_automationHistory);

  SongProject? get activeSong {
    for (final song in _songProjects) {
      if (song.id == _activeSongId) return song;
    }
    return null;
  }

  Future<void> setApiKey(String value) async {
    _apiKey = value.trim();
    if (_apiKey.isEmpty) {
      await _preferences.remove(_apiKeyKey);
    } else {
      await _preferences.setString(_apiKeyKey, _apiKey);
    }
    notifyListeners();
  }

  Future<void> setBackupProvider({
    required String apiKey,
    required String baseUrl,
    required String model,
  }) async {
    _backupApiKey = apiKey.trim();
    _backupBaseUrl = AiProviderConfig.normalizeBaseUrl(baseUrl);
    _backupModel = model.trim().isEmpty
        ? AiProviderConfig.defaultBackupModel
        : model.trim();

    await Future.wait([
      if (_backupApiKey.isEmpty)
        _preferences.remove(_backupApiKeyKey)
      else
        _preferences.setString(_backupApiKeyKey, _backupApiKey),
      _preferences.setString(_backupBaseUrlKey, _backupBaseUrl),
      _preferences.setString(_backupModelKey, _backupModel),
    ]);
    _syncAiProviderConfig();
    notifyListeners();
  }

  void _syncAiProviderConfig() {
    AiProviderConfig.update(
      backupApiKey: _backupApiKey,
      backupBaseUrl: _backupBaseUrl,
      backupModel: _backupModel,
    );
  }

  Future<void> setVoiceRepliesEnabled(bool value) async {
    _voiceRepliesEnabled = value;
    await _preferences.setBool(_voiceRepliesKey, value);
    notifyListeners();
  }

  Future<void> saveVoiceSettings({
    required double rate,
    required double pitch,
    required String voiceName,
    required String voiceLocale,
  }) async {
    _ttsRate = rate.clamp(0.30, 0.70).toDouble();
    _ttsPitch = pitch.clamp(0.70, 1.20).toDouble();
    _ttsVoiceName = voiceName.trim();
    _ttsVoiceLocale = voiceLocale.trim();

    await Future.wait([
      _preferences.setDouble(_ttsRateKey, _ttsRate),
      _preferences.setDouble(_ttsPitchKey, _ttsPitch),
      if (_ttsVoiceName.isEmpty)
        _preferences.remove(_ttsVoiceNameKey)
      else
        _preferences.setString(_ttsVoiceNameKey, _ttsVoiceName),
      if (_ttsVoiceLocale.isEmpty)
        _preferences.remove(_ttsVoiceLocaleKey)
      else
        _preferences.setString(_ttsVoiceLocaleKey, _ttsVoiceLocale),
    ]);
    notifyListeners();
  }

  Future<void> replaceChatHistory(List<ChatMessage> messages) async {
    _chatHistory = messages.length > 80
        ? messages.sublist(messages.length - 80)
        : List<ChatMessage>.from(messages);

    final encoded = jsonEncode(
      _chatHistory.map((message) => message.toJson()).toList(),
    );
    await _preferences.setString(_chatHistoryKey, encoded);
    notifyListeners();
  }

  Future<void> clearChatHistory() async {
    _chatHistory = const [];
    await _preferences.remove(_chatHistoryKey);
    notifyListeners();
  }

  Future<void> saveRapState({
    required String draft,
    required String result,
  }) async {
    _rapDraft = draft;
    _rapResult = result;
    await Future.wait([
      _preferences.setString(_rapDraftKey, draft),
      _preferences.setString(_rapResultKey, result),
    ]);
    notifyListeners();
  }

  Future<void> sendTextToStudio(String text) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return;

    _activeSongId = '';
    _rapDraft = cleanText;
    _rapResult = cleanText;
    _studioRevision++;
    await Future.wait([
      _preferences.setString(_rapDraftKey, _rapDraft),
      _preferences.setString(_rapResultKey, _rapResult),
      _preferences.remove(_activeSongIdKey),
    ]);
    notifyListeners();
  }

  Future<void> loadSongIntoStudio(SongProject song) async {
    _activeSongId = song.id;
    _rapDraft = song.lyrics;
    _rapResult = song.lyrics;
    _studioRevision++;
    await Future.wait([
      _preferences.setString(_rapDraftKey, _rapDraft),
      _preferences.setString(_rapResultKey, _rapResult),
      _preferences.setString(_activeSongIdKey, _activeSongId),
    ]);
    notifyListeners();
  }

  Future<void> startNewStudioProject() async {
    _activeSongId = '';
    _rapDraft = '';
    _rapResult = '';
    _studioRevision++;
    await Future.wait([
      _preferences.remove(_rapDraftKey),
      _preferences.remove(_rapResultKey),
      _preferences.remove(_activeSongIdKey),
    ]);
    notifyListeners();
  }

  Future<SongProject> upsertSong(SongProject project) async {
    final index = _songProjects.indexWhere((item) => item.id == project.id);
    final updated = List<SongProject>.from(_songProjects);
    if (index >= 0) {
      updated[index] = project;
    } else {
      updated.add(project);
    }
    updated.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _songProjects = updated.length > 100
        ? updated.take(100).toList(growable: false)
        : updated;
    _activeSongId = project.id;
    await Future.wait([
      _saveProjects(),
      _preferences.setString(_activeSongIdKey, _activeSongId),
    ]);
    notifyListeners();
    return project;
  }

  Future<void> deleteSong(String id) async {
    _songProjects = _songProjects
        .where((project) => project.id != id)
        .toList(growable: false);
    if (_activeSongId == id) {
      _activeSongId = '';
      await _preferences.remove(_activeSongIdKey);
    }
    await _saveProjects();
    notifyListeners();
  }

  Future<void> toggleAutomationFavorite(String id) async {
    if (_favoriteAutomationIds.contains(id)) {
      _favoriteAutomationIds.remove(id);
    } else {
      _favoriteAutomationIds.add(id);
    }
    await _preferences.setStringList(
      _favoriteAutomationIdsKey,
      _favoriteAutomationIds.toList(growable: false),
    );
    notifyListeners();
  }

  Future<CustomAutomation> upsertCustomAutomation(
    CustomAutomation automation,
  ) async {
    final updated = List<CustomAutomation>.from(_customAutomations);
    final index = updated.indexWhere((item) => item.id == automation.id);
    if (index >= 0) {
      updated[index] = automation;
    } else {
      updated.add(automation);
    }
    updated.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _customAutomations = updated.take(40).toList(growable: false);
    await _saveCustomAutomations();
    notifyListeners();
    return automation;
  }

  Future<void> deleteCustomAutomation(String id) async {
    _customAutomations = _customAutomations
        .where((item) => item.id != id)
        .toList(growable: false);
    _favoriteAutomationIds.remove('custom:$id');
    await Future.wait([
      _saveCustomAutomations(),
      _preferences.setStringList(
        _favoriteAutomationIdsKey,
        _favoriteAutomationIds.toList(growable: false),
      ),
    ]);
    notifyListeners();
  }

  Future<void> addAutomationHistory(AutomationHistoryEntry entry) async {
    final updated = <AutomationHistoryEntry>[
      entry,
      ..._automationHistory.where((item) => item.id != entry.id),
    ];
    _automationHistory = updated.take(30).toList(growable: false);
    await _saveAutomationHistory();
    notifyListeners();
  }

  Future<void> clearAutomationHistory() async {
    _automationHistory = const [];
    await _preferences.remove(_automationHistoryKey);
    notifyListeners();
  }

  Future<void> _saveProjects() async {
    final encoded = jsonEncode(
      _songProjects.map((project) => project.toJson()).toList(),
    );
    await _preferences.setString(_songProjectsKey, encoded);
  }

  Future<void> _saveCustomAutomations() async {
    final encoded = jsonEncode(
      _customAutomations.map((item) => item.toJson()).toList(),
    );
    await _preferences.setString(_customAutomationsKey, encoded);
  }

  Future<void> _saveAutomationHistory() async {
    final encoded = jsonEncode(
      _automationHistory.map((item) => item.toJson()).toList(),
    );
    await _preferences.setString(_automationHistoryKey, encoded);
  }
}
