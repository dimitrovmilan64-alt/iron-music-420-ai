class SpeechErrorPolicy {
  const SpeechErrorPolicy._();

  static bool shouldRetry(String errorMessage) {
    final normalized = errorMessage.trim().toLowerCase();
    return normalized == 'error_speech_timeout' ||
        normalized == 'error_no_match';
  }

  static String friendlyMessage(String errorMessage) {
    final normalized = errorMessage.trim().toLowerCase();

    if (shouldRetry(normalized)) {
      return 'Не чух реч. Натисни микрофона и започни да говориш веднага.';
    }
    if (normalized == 'error_busy' || normalized == 'error_recognizer_busy') {
      return 'Гласовото разпознаване е заето. Изчакай секунда и опитай пак.';
    }
    if (normalized == 'error_permission' ||
        normalized == 'error_permission_denied') {
      return 'Разреши достъп до микрофона за Iron Music 420 AI.';
    }
    if (normalized == 'error_network' ||
        normalized == 'error_network_timeout') {
      return 'Гласовото разпознаване няма връзка с услугата. Провери интернета и опитай пак.';
    }

    return 'Гласовото разпознаване не можа да стартира. Опитай отново.';
  }
}
