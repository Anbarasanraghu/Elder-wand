/// Pulls durable, personal facts out of ordinary sentences so the assistant
/// learns about you from natural conversation — not just explicit "remember
/// that…" commands. Pure Dart (no LLM call), so it's instant and free.
///
/// Deliberately conservative: it only captures clear first-person statements
/// and skips questions, so it doesn't fill your memory with noise.
class MemoryExtractor {
  // Each rule: a pattern + how to phrase the captured fact (second person).
  static final List<(RegExp, String Function(Match))> _rules = [
    (
      RegExp(r"\bi (?:really |absolutely )?(?:like|love|enjoy|prefer) (.+)",
          caseSensitive: false),
      (m) => 'You like ${_clean(m.group(1)!)}'
    ),
    (
      RegExp(r"\bi (?:really )?(?:hate|dislike|can'?t stand) (.+)",
          caseSensitive: false),
      (m) => 'You dislike ${_clean(m.group(1)!)}'
    ),
    (
      RegExp(r"\bmy favou?rite (.+?) (?:is|are) (.+)", caseSensitive: false),
      (m) => 'Your favourite ${_clean(m.group(1)!)} is ${_clean(m.group(2)!)}'
    ),
    (
      RegExp(r"\bi(?:'m| am) allergic to (.+)", caseSensitive: false),
      (m) => "You're allergic to ${_clean(m.group(1)!)}"
    ),
    (
      RegExp(r"\bi(?:'m| am)?\s*learning (.+)", caseSensitive: false),
      (m) => "You're learning ${_clean(m.group(1)!)}"
    ),
    (
      RegExp(r"\bi work (?:at|for) (.+)", caseSensitive: false),
      (m) => 'You work at ${_clean(m.group(1)!)}'
    ),
    (
      RegExp(
          r"\bmy (wife|husband|partner|son|daughter|brother|sister|mom|mother|dad|father|dog|cat|friend)(?:'?s name)? is (.+)",
          caseSensitive: false),
      (m) =>
          'Your ${m.group(1)!.toLowerCase()} is ${_clean(m.group(2)!, keepCaps: true)}'
    ),
    (
      RegExp(r"\bmy birthday (?:is )?(?:on )?(.+)", caseSensitive: false),
      (m) => 'Your birthday is ${_clean(m.group(1)!)}'
    ),
    (
      RegExp(r"\bi have (?:a|an|two|three) (.+)", caseSensitive: false),
      (m) => 'You have ${_clean(m.group(1)!)}'
    ),
  ];

  /// Words that signal it's not a durable fact — skip the whole sentence.
  static final RegExp _skip = RegExp(
      r"\b(would|could|should|do you|are you|what|when|where|why|how|maybe|if|"
      r"today|tonight|tomorrow|yesterday|later|now|going to|gonna|want to|"
      r"need to|please|remind)\b",
      caseSensitive: false);

  /// Extract zero or more facts from [text]. Never throws.
  static List<String> extract(String text) {
    final t = text.trim();
    if (t.length < 6 || t.contains('?') || _skip.hasMatch(t)) return const [];
    final out = <String>[];
    for (final (re, phrase) in _rules) {
      final m = re.firstMatch(t);
      if (m == null) continue;
      final fact = phrase(m).trim();
      if (_valid(fact) && !out.any((f) => f.toLowerCase() == fact.toLowerCase())) {
        out.add(fact);
      }
    }
    return out;
  }

  // Trim a captured phrase to a tidy, short fact.
  static String _clean(String s, {bool keepCaps = false}) {
    var v = s.trim();
    // cut at the first clause boundary so we don't grab a whole ramble
    final cut = RegExp(r'[.,;!?]| and | but | because | so ').firstMatch(v);
    if (cut != null) v = v.substring(0, cut.start);
    v = v.replaceAll(RegExp(r'\s+'), ' ').trim();
    v = v.replaceAll(
        RegExp(r'^(a|an|the|to|some|named|called)\s+', caseSensitive: false),
        '');
    if (!keepCaps) v = v.toLowerCase();
    return v;
  }

  static bool _valid(String fact) {
    final tail = fact.replaceFirst(RegExp(r'^You(?:r|\047re)?\s+\w+\s+'), '');
    return fact.length >= 6 && fact.length <= 60 && tail.isNotEmpty;
  }
}
