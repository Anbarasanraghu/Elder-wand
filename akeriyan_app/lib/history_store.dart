import 'package:flutter/foundation.dart';
import 'local_cache.dart';

/// One line of the conversation transcript.
class ChatEntry {
  final String youSaid;
  final String akeriyanSaid;
  final String intent;
  final DateTime at;

  ChatEntry({
    required this.youSaid,
    required this.akeriyanSaid,
    required this.intent,
    required this.at,
  });

  Map<String, dynamic> toJson() => {
        'youSaid': youSaid,
        'akeriyanSaid': akeriyanSaid,
        'intent': intent,
        'at': at.toIso8601String(),
      };

  factory ChatEntry.fromJson(Map<String, dynamic> j) => ChatEntry(
        youSaid: j['youSaid'] ?? '',
        akeriyanSaid: j['akeriyanSaid'] ?? '',
        intent: j['intent'] ?? '',
        at: DateTime.tryParse(j['at'] ?? '') ?? DateTime.now(),
      );
}

/// In-app transcript so you can see everything AKERIYAN heard and did.
/// Persisted locally (shared_preferences) so it survives restarts and is
/// viewable offline. Uses a ValueNotifier so the history screen updates live.
class HistoryStore {
  static final ValueNotifier<List<ChatEntry>> entries =
      ValueNotifier<List<ChatEntry>>([]);

  /// Load saved history from disk. Call once at startup.
  static Future<void> init() async {
    final data = await LocalCache.load('history');
    if (data is List) {
      entries.value = data
          .whereType<Map>()
          .map((e) => ChatEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
  }

  static void add({
    required String youSaid,
    required String akeriyanSaid,
    required String intent,
  }) {
    final updated = [
      ChatEntry(
        youSaid: youSaid,
        akeriyanSaid: akeriyanSaid,
        intent: intent,
        at: DateTime.now(),
      ),
      ...entries.value,
    ];
    if (updated.length > 200) updated.removeRange(200, updated.length);
    entries.value = updated;
    _persist();
  }

  static void clear() {
    entries.value = [];
    _persist();
  }

  static void _persist() =>
      LocalCache.save('history', entries.value.map((e) => e.toJson()).toList());
}
