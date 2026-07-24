import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Local, on-device personal data — to-do list, notes, journal, habits,
/// expenses and countdown events. All stored in SharedPreferences as JSON;
/// nothing leaves the phone.
class PersonalStore {
  static const _todo = 'ps_todo';
  static const _notes = 'ps_notes';
  static const _journal = 'ps_journal';
  static const _habits = 'ps_habits';
  static const _expenses = 'ps_expenses';
  static const _events = 'ps_events';

  static Future<List<dynamic>> _list(String k) async {
    final s = (await SharedPreferences.getInstance()).getString(k);
    if (s == null) return [];
    try {
      return jsonDecode(s) as List<dynamic>;
    } catch (_) {
      return [];
    }
  }

  static Future<void> _save(String k, List<dynamic> v) async =>
      (await SharedPreferences.getInstance()).setString(k, jsonEncode(v));

  static bool handles(String intent) => const {
        'todo_add', 'todo_list', 'todo_done', 'todo_clear',
        'note_add', 'note_list', 'note_clear',
        'journal_add', 'journal_read',
        'habit_log', 'habit_status',
        'expense_add', 'expense_total',
        'event_set', 'days_until',
      }.contains(intent);

  /// Fulfil a personal-data intent → spoken reply.
  static Future<String> handle(String intent, Map<String, dynamic> s) async {
    switch (intent) {
      case 'todo_add':
        return _todoAdd(s['task'] as String?);
      case 'todo_list':
        return _todoList();
      case 'todo_done':
        return _todoDone(s['task'] as String?);
      case 'todo_clear':
        return _clear(_todo, 'to-do list');
      case 'note_add':
        return _noteAdd(s['text'] as String?);
      case 'note_list':
        return _noteList();
      case 'note_clear':
        return _clear(_notes, 'notes');
      case 'journal_add':
        return _journalAdd(s['text'] as String?);
      case 'journal_read':
        return _journalRead();
      case 'habit_log':
        return _habitLog(s['name'] as String?);
      case 'habit_status':
        return _habitStatus(s['name'] as String?);
      case 'expense_add':
        return _expenseAdd((s['amount'] as num).toDouble(), s['category'] as String?);
      case 'expense_total':
        return _expenseTotal(s['period'] == 'week');
      case 'event_set':
        return _eventSet(s['name'] as String?, s['date'] as String?);
      case 'days_until':
        return _daysUntil(s['name'] as String?, s['date'] as String?);
    }
    return '';
  }

  // ---- to-do ----
  static Future<String> _todoAdd(String? task) async {
    task = (task ?? '').trim();
    if (task.isEmpty) return 'What should I add to your list?';
    final l = await _list(_todo);
    l.add({'t': task, 'done': false});
    await _save(_todo, l);
    return 'Added "$task" to your list.';
  }

  static Future<String> _todoList() async {
    final l = (await _list(_todo)).where((e) => e['done'] != true).toList();
    if (l.isEmpty) return 'Your list is empty.';
    final items = [for (var i = 0; i < l.length; i++) '${i + 1}. ${l[i]['t']}']
        .join(', ');
    return "You have ${l.length} thing${l.length != 1 ? 's' : ''} to do: $items.";
  }

  static Future<String> _todoDone(String? q) async {
    q = (q ?? '').trim().toLowerCase();
    if (q.isEmpty) return 'Which one is done?';
    final l = await _list(_todo);
    for (final e in l) {
      if (e['done'] != true &&
          (e['t'] as String).toLowerCase().contains(q)) {
        e['done'] = true;
        await _save(_todo, l);
        return 'Marked "${e['t']}" as done.';
      }
    }
    return 'I couldn\'t find "$q" on your list.';
  }

  static Future<String> _clear(String key, String label) async {
    await _save(key, []);
    return 'Cleared your $label.';
  }

  // ---- notes ----
  static Future<String> _noteAdd(String? text) async {
    text = (text ?? '').trim();
    if (text.isEmpty) return 'What should I note down?';
    final l = await _list(_notes);
    l.add({'t': text, 'at': DateTime.now().toIso8601String()});
    await _save(_notes, l);
    return 'Noted.';
  }

  static Future<String> _noteList() async {
    final l = await _list(_notes);
    if (l.isEmpty) return 'You have no notes yet.';
    final items = [for (var i = 0; i < l.length; i++) '${i + 1}. ${l[i]['t']}']
        .join('. ');
    return 'Your notes: $items.';
  }

  // ---- journal ----
  static Future<String> _journalAdd(String? text) async {
    text = (text ?? '').trim();
    if (text.isEmpty) return 'What would you like to journal?';
    final l = await _list(_journal);
    l.add({'t': text, 'at': DateTime.now().toIso8601String()});
    await _save(_journal, l);
    return 'Added to your journal.';
  }

  static Future<String> _journalRead() async {
    final l = await _list(_journal);
    if (l.isEmpty) return 'Your journal is empty.';
    final recent = l.length <= 3 ? l : l.sublist(l.length - 3);
    return 'Your recent journal entries: ${recent.map((e) => e['t']).join('. ')}.';
  }

  // ---- habits ----
  static String _dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  static int _streak(List<String> days) {
    final set = days.toSet();
    var n = 0;
    var d = DateTime.now();
    if (!set.contains(_dayKey(d))) d = d.subtract(const Duration(days: 1));
    while (set.contains(_dayKey(d))) {
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }

  static Future<String> _habitLog(String? name) async {
    name = (name ?? '').trim();
    if (name.isEmpty) return 'Which habit did you do?';
    final l = await _list(_habits);
    Map<String, dynamic>? h;
    for (final e in l) {
      if ((e['n'] as String).toLowerCase() == name.toLowerCase()) {
        h = e as Map<String, dynamic>;
        break;
      }
    }
    if (h == null) {
      h = {'n': name, 'days': <String>[]};
      l.add(h);
    }
    final days = (h['days'] as List).cast<String>();
    final today = _dayKey(DateTime.now());
    if (!days.contains(today)) days.add(today);
    h['days'] = days;
    await _save(_habits, l);
    final s = _streak(days);
    return "Nice — logged $name. That's a $s day streak.";
  }

  static Future<String> _habitStatus(String? name) async {
    name = (name ?? '').trim();
    final l = await _list(_habits);
    for (final e in l) {
      if ((e['n'] as String).toLowerCase() == name.toLowerCase()) {
        final days = (e['days'] as List).cast<String>();
        final doneToday = days.contains(_dayKey(DateTime.now()));
        return '$name: ${doneToday ? "done today" : "not done today"}, '
            '${_streak(days)} day streak.';
      }
    }
    return "You're not tracking $name yet. Say 'log habit $name'.";
  }

  // ---- expenses ----
  static Future<String> _expenseAdd(double amount, String? cat) async {
    cat = (cat ?? 'something').trim();
    final l = await _list(_expenses);
    l.add({'a': amount, 'c': cat, 'at': DateTime.now().toIso8601String()});
    await _save(_expenses, l);
    return 'Logged ${amount.round()} for $cat.';
  }

  static Future<String> _expenseTotal(bool week) async {
    final l = await _list(_expenses);
    final since = week
        ? DateTime.now().subtract(const Duration(days: 7))
        : DateTime(2000);
    var total = 0.0;
    for (final e in l) {
      final at = DateTime.tryParse(e['at'] as String? ?? '');
      if (at != null && at.isAfter(since)) total += (e['a'] as num).toDouble();
    }
    return "You've spent ${total.round()} ${week ? 'this week' : 'in total'}.";
  }

  // ---- countdown events ----
  static Future<String> _eventSet(String? name, String? iso) async {
    name = (name ?? '').trim();
    if (name.isEmpty || iso == null) return 'Tell me the event and its date.';
    final l = await _list(_events);
    l.removeWhere((e) => (e['n'] as String).toLowerCase() == name!.toLowerCase());
    l.add({'n': name, 'd': iso});
    await _save(_events, l);
    return "Got it — I'll count down to $name.";
  }

  static Future<String> _daysUntil(String? name, String? iso) async {
    DateTime? target = iso != null ? DateTime.tryParse(iso) : null;
    if (target == null && name != null) {
      final l = await _list(_events);
      for (final e in l) {
        if (name.toLowerCase().contains((e['n'] as String).toLowerCase())) {
          target = DateTime.tryParse(e['d'] as String? ?? '');
          break;
        }
      }
    }
    if (target == null) {
      return "I don't know that date. Say a date like December 25, "
          "or tell me '${name ?? 'it'} is on <date>'.";
    }
    final now = DateTime.now();
    final days = target.difference(DateTime(now.year, now.month, now.day)).inDays;
    if (days < 0) return 'That date has already passed.';
    if (days == 0) return "That's today!";
    return "$days day${days != 1 ? 's' : ''} until ${name ?? 'then'}.";
  }
}
