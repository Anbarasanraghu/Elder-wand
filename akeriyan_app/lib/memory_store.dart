import 'package:flutter/foundation.dart';

import 'local_cache.dart';

/// Long-term facts the assistant should always know about you — your name,
/// where you live, what you do, your preferences. Unlike the rolling chat
/// history, these are permanent: they're persisted and injected into the
/// on-device brain every time it loads, so Elder Wand remembers you like a
/// real personal assistant across restarts.
class MemoryStore {
  static final ValueNotifier<List<String>> facts =
      ValueNotifier<List<String>>([]);
  static const int _cap = 60;

  /// Load saved facts from disk. Call once at startup.
  static Future<void> init() async {
    final data = await LocalCache.load('memory_facts');
    if (data is List) {
      facts.value = data.map((e) => '$e').where((s) => s.isNotEmpty).toList();
    }
  }

  /// Add a fact (deduped, case-insensitive). Newest first.
  static void add(String fact) {
    fact = fact.trim();
    if (fact.isEmpty) return;
    final lower = fact.toLowerCase();
    final next = facts.value
        .where((f) => f.toLowerCase() != lower)
        .toList()
      ..insert(0, fact);
    if (next.length > _cap) next.removeRange(_cap, next.length);
    facts.value = next;
    _persist();
  }

  static void removeAt(int i) {
    if (i < 0 || i >= facts.value.length) return;
    final next = [...facts.value]..removeAt(i);
    facts.value = next;
    _persist();
  }

  static void clear() {
    facts.value = [];
    _persist();
  }

  /// One-line summary fed into the model's system instruction.
  static String summaryForPrompt() => facts.value.join('; ');

  /// A spoken read-back of what the assistant knows.
  static String spoken() {
    if (facts.value.isEmpty) {
      return "I don't know much about you yet. Tell me things like "
          "'my name is Alex' or 'remember that I trade gold'.";
    }
    return "Here's what I remember about you: ${facts.value.join('. ')}.";
  }

  static void _persist() => LocalCache.save('memory_facts', facts.value);
}
