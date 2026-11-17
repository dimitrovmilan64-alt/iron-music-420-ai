/// Classifies short spoken chat transcripts so fragments are not sent
/// to the model, and so "стоп" can cancel an in-flight reply.
class VoiceUtterance {
  static const fragmentRepeatMessage =
      'Не чух цялото изречение. Кажи го отново след сигнала.';

  static const cancelledMessage = 'Отговорът е спрян.';

  static const timeoutMessage =
      'Няма отговор до 25 секунди. Провери връзката и опитай отново.';

  static const cancelHintMessage =
      'Изчаквам отговор. Натисни „Стоп“ или кажи „стоп“, за да го прекъснеш.';

  static const _cancelPhrases = <String>{
    'стоп',
    'stop',
    'спри',
    'cancel',
    'откажи',
    'отказ',
    'прекъсни',
    'спри го',
    'stop it',
    'cancel it',
  };

  static const _shortAcknowledgements = <String>{
    'да',
    'не',
    'ок',
    'окей',
    'okay',
    'ok',
    'yes',
    'no',
    'yeah',
    'здрасти',
    'здравей',
    'привет',
    'hello',
    'hi',
    'hey',
    'благодаря',
    'мерси',
    'thanks',
  };

  static const _tailStarters = <String>{
    'и',
    'а',
    'но',
    'че',
    'или',
    'така',
    'защото',
    'and',
    'but',
    'or',
    'so',
    'because',
  };

  static const _incompleteEndings = <String>{
    'една',
    'един',
    'едно',
    'едни',
    'това',
    'онази',
    'онова',
    'този',
    'някой',
    'някоя',
    'някое',
    'някакъв',
    'някаква',
    'the',
    'a',
    'an',
    'to',
    'for',
    'with',
  };

  static String normalize(String raw) {
    return raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[.!?,;:…„“”"«»()]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool isCancelCommand(String raw) {
    final text = normalize(raw);
    if (text.isEmpty) return false;
    if (_cancelPhrases.contains(text)) return true;
    final words = text.split(' ');
    if (words.length <= 3 && words.any(_cancelPhrases.contains)) {
      return true;
    }
    return false;
  }

  /// Incomplete tails such as "и тя има една" must be repeated, not sent.
  static bool isFragment(String raw) {
    final text = normalize(raw);
    if (text.isEmpty) return true;
    if (isCancelCommand(text)) return false;
    if (_shortAcknowledgements.contains(text)) return false;
    final words = text.split(' ');
    if (words.length == 1 && text.length < 6) return true;
    if (words.length <= 4 && _tailStarters.contains(words.first)) return true;
    if (words.length <= 5 && _incompleteEndings.contains(words.last)) {
      return true;
    }
    return false;
  }
}
