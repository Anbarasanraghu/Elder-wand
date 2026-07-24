import 'on_device_skills.dart';

/// On-device command understanding — a Dart port of the backend's fast rules,
/// for the intents the PHONE can fully handle without the server. Returns an
/// {intent, slots, speak} map, or null for anything that should go to the
/// on-device chat (Gemma) or the backend (email/CRM/trading/…).
class OnDeviceNlu {
  static const _numWords = {
    'one': '1', 'two': '2', 'three': '3', 'four': '4', 'five': '5',
    'six': '6', 'seven': '7', 'eight': '8', 'nine': '9', 'ten': '10',
    'eleven': '11', 'twelve': '12', 'fifteen': '15', 'twenty': '20',
    'thirty': '30', 'forty': '40', 'forty five': '45', 'fifty': '50',
    'sixty': '60', 'half an': '0.5',
  };

  static String _digits(String t) {
    final keys = _numWords.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final w in keys) {
      t = t.replaceAll(RegExp('\\b$w\\b'), _numWords[w]!);
    }
    return t;
  }

  static Map<String, dynamic>? parse(String raw) {
    var t = raw.toLowerCase().trim().replaceAll(RegExp(r'[.!?]+$'), '');
    t = _digits(t);

    // ---- reminders (with time parsing) ----
    if (t.contains('remind me') || t.startsWith('reminder')) {
      final recurrence =
          RegExp(r'\bevery ?day\b|\bdaily\b').hasMatch(t) ? 'FREQ=DAILY' : null;
      final due = _parseTime(t) ?? _parseRelative(t);
      var task = t.replaceFirst(RegExp(r'^.*?remind me( to)?\s*'), '');
      task = task
          .replaceAll(
              RegExp(r'\b(at |in )?\d{1,2}([:\s]\d{2})?\s*(am|pm)\b.*$'), '')
          .replaceAll(RegExp(r'\bin \d+(\.\d+)? (minutes?|hours?)\b.*$'), '')
          .replaceAll(RegExp(r'\bevery ?day\b|\bdaily\b'), '')
          .trim();
      if (task.isEmpty) task = 'your task';
      String speak;
      if (due != null) {
        final when = _fmt(due);
        speak = 'Reminder set for $when${recurrence != null ? ', every day' : ''}: $task.';
      } else {
        speak =
            "I heard the reminder '$task', but no time. Say a time like 8 PM.";
      }
      return {
        'intent': 'create_reminder',
        'slots': {
          'text': task,
          'time': due?.toIso8601String(),
          'recurrence': recurrence,
        },
        'speak': speak,
      };
    }

    // ---- timer ----
    if (t.contains('timer') ||
        RegExp(r'\bset (a|an)\b.*\b(minute|second|hour)').hasMatch(t)) {
      final secs = _parseSeconds(t);
      if (secs > 0) {
        final mins = secs ~/ 60;
        final human =
            mins > 0 ? '$mins minute${mins != 1 ? 's' : ''}' : '$secs seconds';
        return {
          'intent': 'set_timer',
          'slots': {'seconds': secs},
          'speak': 'Timer set for $human.',
        };
      }
    }

    // ---- flashlight ----
    if (t.contains('flashlight') || t.contains('torch')) {
      final state = (t.contains('off') || t.contains('turn out')) ? 'off' : 'on';
      return {
        'intent': 'toggle_flashlight',
        'slots': {'state': state},
        'speak': 'Turning the flashlight $state.',
      };
    }

    // ---- battery ----
    if (RegExp(r'\bbattery\b').hasMatch(t) ||
        RegExp(r'\bhow much (charge|power)\b').hasMatch(t) ||
        RegExp(r'\bcharge (left|remaining)\b').hasMatch(t)) {
      return {'intent': 'battery', 'slots': {}, 'speak': ''};
    }

    // ---- redial / call last ----
    if (RegExp(r'\b(redial|call back|call (back |the )?last (person|number|caller|call))\b')
        .hasMatch(t)) {
      return {'intent': 'redial', 'slots': {}, 'speak': ''};
    }

    // ---- read messages ----
    if (RegExp(r'\bmessages?\b').hasMatch(t) &&
        RegExp(r'\b(any|new|unread|read|check|show|latest|got)\b').hasMatch(t) &&
        !RegExp(r'\b(send|tell|reply|to)\b').hasMatch(t)) {
      return {
        'intent': 'read_notifications',
        'slots': {'kind': 'messages'},
        'speak': '',
      };
    }

    // ---- notifications ----
    if (t.contains('notification')) {
      return {
        'intent': 'read_notifications',
        'slots': {'kind': t.contains('all') ? 'all' : 'latest'},
        'speak': '',
      };
    }

    // ================= LONG-TERM MEMORY (facts about you) =================
    // recall
    if (RegExp(r'\bwhat do you (remember|know) about me\b').hasMatch(t) ||
        t == 'what do you remember') {
      return {'intent': 'memory_recall', 'slots': {}, 'speak': ''};
    }
    // forget everything
    if (RegExp(r'\bforget (everything|what you know|all)\b').hasMatch(t) &&
        t.contains('me')) {
      return {'intent': 'memory_forget', 'slots': {}, 'speak': ''};
    }
    // explicit: "remember that I trade gold" (but NOT "remember to …")
    final rememberThat =
        RegExp(r'^(?:please\s+)?remember (?:that |this[: ]|)(.+)$').firstMatch(t);
    if (rememberThat != null && !t.startsWith('remember to')) {
      return {
        'intent': 'memory_add',
        'slots': {'fact': _asFact(rememberThat.group(1)!)},
        'speak': '',
      };
    }
    // "my name is Alex"
    final nameIs = RegExp(r'\bmy name is (.+)$').firstMatch(t);
    if (nameIs != null) {
      final name = _titleCase(nameIs.group(1)!.trim());
      return {
        'intent': 'memory_add',
        'slots': {'fact': 'Your name is $name'},
        'speak': "Nice to meet you, $name. I'll remember that.",
      };
    }
    // "I live in Chennai" / "I'm from Chennai"
    final liveIn =
        RegExp(r"\bi(?:'?m| am)? (?:live in|from|based in|stay in) (.+)$")
            .firstMatch(t);
    if (liveIn != null) {
      return {
        'intent': 'memory_add',
        'slots': {'fact': 'You live in ${_titleCase(liveIn.group(1)!.trim())}'},
        'speak': '',
      };
    }
    // "I work as a teacher" / "my job is …"
    final jobIs = RegExp(
            r'\b(?:i work as|i work at|my job is|my profession is)\s+(.+)$')
        .firstMatch(t);
    if (jobIs != null) {
      return {
        'intent': 'memory_add',
        'slots': {'fact': 'You work as ${jobIs.group(1)!.trim()}'},
        'speak': '',
      };
    }
    // ====================================================================

    // ================= SYSTEM ACTIONS (Batch 4) =================
    // brain persona: trading vs general
    if (RegExp(r'\b(trading|trader|forex|gold|scalp) mode\b').hasMatch(t) ||
        RegExp(r'\b(switch to|go to|enter|enable) (trading|forex)\b').hasMatch(t)) {
      return {'intent': 'set_mode', 'slots': {'mode': 'trading'}, 'speak': ''};
    }
    if (RegExp(r'\b(normal|general|assistant|default|chat) mode\b').hasMatch(t) ||
        RegExp(r'\b(switch to|go to|back to) (normal|general)\b').hasMatch(t) ||
        RegExp(r'\b(exit|leave|turn off) (trading|forex) mode\b').hasMatch(t)) {
      return {'intent': 'set_mode', 'slots': {'mode': 'general'}, 'speak': ''};
    }
    // open the full app ("open our space") — from the floating overlay
    if (RegExp(r'\bopen (our space|the app|the assistant|elder wand|you|yourself|full app)\b')
            .hasMatch(t) ||
        t == 'our space' ||
        t == 'open up') {
      return {'intent': 'open_self', 'slots': {}, 'speak': ''};
    }
    // alarm: "set an alarm for 7am", "wake me up at 6:30"
    if (RegExp(r'\balarm\b').hasMatch(t) ||
        RegExp(r'\bwake me( up)?\b').hasMatch(t)) {
      final due = _parseTime(t);
      if (due != null) {
        var label = t
            .replaceAll(RegExp(r'\b(set|an?|the|for|to|please|wake me up|wake me)\b'), '')
            .replaceAll(RegExp(r'\balarm\b'), '')
            .replaceAll(RegExp(r'\b(at\s+)?\d{1,2}([:\s]\d{2})?\s*(am|pm)?\b.*$'), '')
            .trim();
        return {
          'intent': 'set_alarm',
          'slots': {
            'hour': due.hour,
            'minute': due.minute,
            'label': label.isEmpty ? null : label,
          },
          'speak': '',
        };
      }
    }
    // calendar: "schedule a meeting at 3pm", "add dentist to my calendar"
    if (RegExp(r'\bcalendar\b').hasMatch(t) ||
        RegExp(r'\b(schedule|meeting|appointment)\b').hasMatch(t)) {
      final due = _parseTime(t) ?? _parseRelative(t);
      if (due != null) {
        var title = t
            .replaceAll(
                RegExp(r'\b(add|put|create|schedule|set up|new|make)\b'), '')
            .replaceAll(
                RegExp(
                    r'\b(a|an|the|to|on|my|in|for|with|event|meeting|appointment|reminder|calendar)\b'),
                '')
            .replaceAll(
                RegExp(r'\b(at\s+)?\d{1,2}([:\s]\d{2})?\s*(am|pm)\b.*$'), '')
            .replaceAll(RegExp(r'\bin \d+(\.\d+)? (minutes?|hours?)\b.*$'), '')
            .replaceAll(RegExp(r'\b(today|tonight|tomorrow|next \w+)\b'), '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        if (title.isEmpty) title = 'New event';
        return {
          'intent': 'calendar_event',
          'slots': {'title': title, 'time': due.toIso8601String()},
          'speak': '',
        };
      }
    }
    // music: "play despacito", "play some music", "play X on spotify"
    final music = RegExp(r'^play\s+(.+)$').firstMatch(t);
    if (music != null) {
      var q = music
          .group(1)!
          .replaceAll(
              RegExp(r'\b(some|a|the)\s+|\b(song|songs|music|track|tune)s?\b'),
              '')
          .replaceAll(
              RegExp(
                  r'\bon (spotify|youtube( music)?|apple music|gaana|wynk|amazon music)\b'),
              '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      return {'intent': 'play_music', 'slots': {'query': q}, 'speak': ''};
    }
    // scan: QR / barcode vs text (OCR)
    if (RegExp(r'\bscan\b').hasMatch(t) || t.contains('ocr')) {
      final ocr = RegExp(r'\b(text|document|paper|note|sign|words?|ocr)\b')
          .hasMatch(t);
      return {
        'intent': ocr ? 'scan_text' : 'scan_qr',
        'slots': {},
        'speak': '',
      };
    }
    if (RegExp(r'\bread (this|the) (document|text|paper|sign|note)\b')
        .hasMatch(t)) {
      return {'intent': 'scan_text', 'slots': {}, 'speak': ''};
    }
    // vision: ask the multimodal brain about a photo (scene understanding,
    // not text — OCR above handles reading text).
    if (RegExp(r"\bwhat(?:'s| is| are)? (?:in|on) (?:this|the|my) (?:image|photo|picture|pic|camera|screen)\b")
            .hasMatch(t) ||
        RegExp(r'\b(describe|analy[sz]e|look at|check|see) (?:this|the|my) (?:photo|image|picture|pic|scene|surroundings?)\b')
            .hasMatch(t) ||
        RegExp(r'\bwhat (?:am i looking at|do you see|is this)\b').hasMatch(t) ||
        t == 'read this image' ||
        t == 'read the image') {
      return {
        'intent': 'vision_ask',
        'slots': {'question': raw.trim()},
        'speak': '',
      };
    }
    // ==========================================================

    // ================= PERSONAL DATA (all on-device) =================
    // to-do list
    final todoAdd = RegExp(
            r'^(?:add|put)\s+(.+?)\s+(?:to|on)\s+(?:my\s+)?(?:to-?do list|todo list|to do list|list|tasks?)$')
        .firstMatch(t);
    if (todoAdd != null) {
      return {'intent': 'todo_add', 'slots': {'task': todoAdd.group(1)!.trim()}, 'speak': ''};
    }
    if (RegExp(r"\b(what'?s on my|read my|show my|check my)\b.*\b(list|to-?dos?|tasks?)\b")
            .hasMatch(t) ||
        {'my list', 'my tasks', 'my to-do list', 'my todo list', 'my to do list'}.contains(t)) {
      return {'intent': 'todo_list', 'slots': {}, 'speak': ''};
    }
    if (RegExp(r'\bclear (my )?(list|to-?dos?|tasks?)\b').hasMatch(t)) {
      return {'intent': 'todo_clear', 'slots': {}, 'speak': ''};
    }
    final todoDone = RegExp(r'^mark\s+(.+?)\s+(?:as\s+)?done$').firstMatch(t) ??
        RegExp(r'^(?:done with|completed?|finished|cross off|remove)\s+(.+?)(?:\s+from (?:my )?list)?$')
            .firstMatch(t);
    if (todoDone != null) {
      return {'intent': 'todo_done', 'slots': {'task': todoDone.group(1)!.trim()}, 'speak': ''};
    }

    // notes
    final noteAdd = RegExp(
            r'^(?:take a note|make a note|note that|note down|new note|note)[:\s]+(.+)$')
        .firstMatch(t);
    if (noteAdd != null) {
      return {'intent': 'note_add', 'slots': {'text': noteAdd.group(1)!.trim()}, 'speak': ''};
    }
    if (RegExp(r'\b(read|show|what are) my notes\b').hasMatch(t) || t == 'my notes') {
      return {'intent': 'note_list', 'slots': {}, 'speak': ''};
    }
    if (RegExp(r'\bclear (my )?notes\b').hasMatch(t)) {
      return {'intent': 'note_clear', 'slots': {}, 'speak': ''};
    }

    // journal
    final jAdd = RegExp(r'^(?:journal|diary|dear diary|add to (?:my )?journal)[:\s]+(.+)$')
        .firstMatch(t);
    if (jAdd != null) {
      return {'intent': 'journal_add', 'slots': {'text': jAdd.group(1)!.trim()}, 'speak': ''};
    }
    if (RegExp(r'\b(read|show)\b.*\b(journal|diary)\b').hasMatch(t) || t == 'my journal') {
      return {'intent': 'journal_read', 'slots': {}, 'speak': ''};
    }

    // habits
    final hLog = RegExp(r'^(?:log|track|check off|did)\s+(?:my\s+)?(.+?)\s+habit\b').firstMatch(t) ??
        RegExp(r'^(?:log|track)\s+habit\s+(.+)$').firstMatch(t);
    if (hLog != null) {
      return {'intent': 'habit_log', 'slots': {'name': hLog.group(1)!.trim()}, 'speak': ''};
    }
    final hStat = RegExp(r'\b(?:my|the)\s+(.+?)\s+(?:habit|streak)\b').firstMatch(t);
    if (hStat != null) {
      return {'intent': 'habit_status', 'slots': {'name': hStat.group(1)!.trim()}, 'speak': ''};
    }

    // expenses
    final exp = RegExp(
            r'\b(?:spent|spend|paid)\s+(\d+(?:\.\d+)?)\s*(?:rupees|rs|dollars|bucks)?\s*(?:on|for)\s+(.+)$')
        .firstMatch(t);
    if (exp != null) {
      return {
        'intent': 'expense_add',
        'slots': {'amount': double.parse(exp.group(1)!), 'category': exp.group(2)!.trim()},
        'speak': '',
      };
    }
    if (RegExp(r'\b(how much (did|have) i spent?|my (expenses|spending)|total (expenses|spending))\b')
        .hasMatch(t)) {
      return {
        'intent': 'expense_total',
        'slots': {'period': t.contains('week') ? 'week' : 'all'},
        'speak': '',
      };
    }

    // countdown events
    final evSet = RegExp(r'^(?:my )?(.+?)\s+is on\s+(.+)$').firstMatch(t);
    if (evSet != null) {
      final d = _parseDate(evSet.group(2)!);
      if (d != null) {
        return {
          'intent': 'event_set',
          'slots': {'name': evSet.group(1)!.trim(), 'date': d.toIso8601String()},
          'speak': '',
        };
      }
    }
    final dUntil = RegExp(r'\bhow many days (?:until|till|to)\s+(.+)$').firstMatch(t);
    if (dUntil != null) {
      final name = dUntil.group(1)!.trim();
      final d = _parseDate(name);
      return {
        'intent': 'days_until',
        'slots': {'name': name, 'date': d?.toIso8601String()},
        'speak': '',
      };
    }
    // =================================================================

    // ================= FINANCE (free APIs, on-device) =================
    // Currency noun, optionally preceded by a nationality adjective so
    // "us dollars", "indian rupees", "british pounds" all parse.
    const curNoun =
        r'(?:dollars?|rupees?|euros?|pounds?|yen|bucks?|usd|inr|eur|gbp|jpy|aud|cad|rs)';
    const adj =
        r'(?:us|u\.?s\.?|american|indian|british|uk|australian|canadian|japanese|singapore)?\s*';
    // "20 us dollars" -> amount + source currency
    final amtM = RegExp('\\b(\\d+(?:\\.\\d+)?)\\s*$adj($curNoun)\\b').firstMatch(t);
    // every currency mentioned, in order
    final curList =
        RegExp('$adj($curNoun)').allMatches(t).map((m) => m.group(1)!).toList();
    final financeWord =
        RegExp(r'\b(rate|convert|conversion|exchange|worth|equals?|how much)\b')
            .hasMatch(t);
    final isExpense = RegExp(r'\b(spent|spend|paid|budget)\b').hasMatch(t);
    if (curList.isNotEmpty &&
        !isExpense &&
        (amtM != null || curList.length >= 2 || financeWord)) {
      String otherThan(String c) => curList.firstWhere(
            (x) => OnDeviceSkills.curCode(x) != OnDeviceSkills.curCode(c),
            orElse: () => OnDeviceSkills.curCode(c) == 'INR' ? 'usd' : 'rupees',
          );
      if (amtM != null) {
        final from = amtM.group(2)!;
        return {
          'intent': 'currency_convert',
          'slots': {
            'amount': double.parse(amtM.group(1)!),
            'from': from,
            'to': otherThan(from),
          },
          'speak': '',
        };
      }
      final from = curList.first;
      return {
        'intent': 'currency_rate',
        'slots': {'from': from, 'to': otherThan(from)},
        'speak': '',
      };
    }
    if (RegExp(r'\b(dollar|usd) (rate|value|price)\b').hasMatch(t)) {
      return {
        'intent': 'currency_rate',
        'slots': {'from': 'dollar', 'to': 'rupee'},
        'speak': '',
      };
    }
    // crypto price
    final coinM = RegExp(
            r'\b(bitcoin|btc|ethereum|eth|solana|sol|dogecoin|doge|cardano|ada|ripple|xrp|binance coin|bnb|litecoin|ltc|polkadot|chainlink|avalanche)\b')
        .firstMatch(t);
    if (coinM != null &&
        (t.contains('price') ||
            t.contains('worth') ||
            t.contains('cost') ||
            t.contains('value') ||
            RegExp(r'\bhow much (is|are)\b').hasMatch(t))) {
      return {'intent': 'crypto_price', 'slots': {'coin': coinM.group(1)!}, 'speak': ''};
    }
    // =================================================================

    // ---- weather ----
    if (RegExp(r'\b(weather|temperature|forecast|how (hot|cold|warm)|will it rain|raining|humidity)\b')
        .hasMatch(t)) {
      final cm = RegExp(r'\b(?:in|at|for)\s+([a-z .\-]{2,40})$').firstMatch(t);
      return {
        'intent': 'weather',
        'slots': {'city': cm?.group(1)?.trim()},
        'speak': '',
      };
    }

    // ---- news ----
    if (t.contains('news') || t.contains('headlines')) {
      final tm = RegExp(r'\b(?:about|on)\s+(.+)$').firstMatch(t);
      return {
        'intent': 'news',
        'slots': {'topic': tm?.group(1)?.trim()},
        'speak': '',
      };
    }

    // ---- briefing ----
    if (t.contains('briefing') ||
        t.contains('brief me') ||
        RegExp(r'^good morning( elder wand)?$').hasMatch(t)) {
      return {'intent': 'briefing', 'slots': {}, 'speak': ''};
    }

    // ---- web search ----
    final sm = RegExp(r'\b(search (for )?|look ?up|google)\b').firstMatch(t);
    if (sm != null) {
      final q = t.substring(sm.end).trim();
      if (q.isNotEmpty) {
        return {'intent': 'web_search', 'slots': {'query': q}, 'speak': ''};
      }
    }

    // ---- math ----
    if (RegExp(r"\b(calculate|what is|whats|what's|how much is)\b.*\d").hasMatch(t) ||
        RegExp(r'\d+\s*(plus|minus|times|multiplied|divided|into|percent|power|\+|\-|\*|/|x)\b')
            .hasMatch(t)) {
      return {'intent': 'math', 'slots': {'expression': t}, 'speak': ''};
    }

    // ---- open app ----
    final om = RegExp(r'\bopen\s+(.+)$').firstMatch(t);
    if (om != null) {
      final app = om.group(1)!.trim();
      return {
        'intent': 'open_app',
        'slots': {'app': app},
        'speak': 'Opening $app.',
      };
    }

    // ---- phone call ----
    final cm = RegExp(r'\b(?:call|dial|phone|ring)\s+([a-z]+)').firstMatch(t);
    if (cm != null && !t.contains('whatsapp')) {
      final name = cm.group(1)!;
      if (!['me', 'up', 'the', 'a', 'back'].contains(name)) {
        return {
          'intent': 'phone_call',
          'slots': {'contact': name},
          'speak': 'Calling $name.',
        };
      }
    }

    // ---- whatsapp / text ----
    if (t.contains('whatsapp') ||
        (t.contains('message') && (t.contains('send') || t.contains('tell'))) ||
        t.startsWith('tell ') ||
        t.startsWith('text ')) {
      final nm = RegExp(r'\b(?:to|tell|text|message)\s+([a-z]+)').firstMatch(t);
      String? name = nm?.group(1);
      if (['a', 'the', 'whatsapp', 'message', 'him', 'her', 'them']
          .contains(name)) {
        name = null;
      }
      String? message;
      final mm =
          RegExp(r'(?:saying|message was|that says?|:|that)\s+(.+)$').firstMatch(t);
      message = mm?.group(1)?.trim();
      return {
        'intent': 'whatsapp_send',
        'slots': {'contact': name, 'message': message},
        'speak': name == null ? 'Who should I message?' : '',
      };
    }

    // ---- time (always from the device clock, never guessed) ----
    if (RegExp(r'\btime\b').hasMatch(t) &&
        RegExp(r'\b(what|whats|current|now|tell|the|is it)\b').hasMatch(t)) {
      return {'intent': 'smalltalk', 'slots': {}, 'speak': 'It is ${_clock()}.'};
    }
    // ---- date / day / year / month (from the device clock) ----
    if (RegExp(r'\b(date|today|todays|day|year|month)\b').hasMatch(t) &&
        RegExp(r"\b(what|what'?s|whats|which|current|tell me|today|todays|is it|of the)\b")
            .hasMatch(t) &&
        !t.contains('remind') &&
        !t.contains('birthday') &&
        !t.contains('timer') &&
        !RegExp(r'\bdays (until|till|to)\b').hasMatch(t)) {
      return {'intent': 'smalltalk', 'slots': {}, 'speak': _dateSpoken(t)};
    }

    // ---- greeting ----
    if (RegExp(r'^(hi|hello|hey)( elder wand)?$').hasMatch(t)) {
      return {
        'intent': 'smalltalk',
        'slots': {},
        'speak': "Yes, I'm listening.",
      };
    }

    return null; // let Gemma / backend handle it
  }

  // ---------- time helpers ----------
  static DateTime? _parseTime(String text) {
    var t = text
        .replaceAll(RegExp(r'\bp\.?\s?m\.?\b'), 'pm')
        .replaceAll(RegExp(r'\ba\.?\s?m\.?\b'), 'am');
    final m = RegExp(r'\b(\d{1,2})(?:[:\s](\d{2}))?\s*(am|pm)\b').firstMatch(t);
    int hour, minute;
    if (m != null) {
      hour = int.parse(m.group(1)!);
      minute = int.parse(m.group(2) ?? '0');
      if (hour < 1 || hour > 12 || minute > 59) return null;
      if (m.group(3) == 'pm' && hour != 12) hour += 12;
      if (m.group(3) == 'am' && hour == 12) hour = 0;
    } else {
      final m24 = RegExp(r'\bat\s+(\d{1,2})[:\s](\d{2})\b').firstMatch(t);
      if (m24 == null) return null;
      hour = int.parse(m24.group(1)!);
      minute = int.parse(m24.group(2)!);
      if (hour > 23 || minute > 59) return null;
    }
    final now = DateTime.now();
    var due = DateTime(now.year, now.month, now.day, hour, minute);
    if (!due.isAfter(now)) due = due.add(const Duration(days: 1));
    return due;
  }

  static DateTime? _parseRelative(String text) {
    final m = RegExp(
            r'\bin\s+(\d+(?:\.\d+)?)\s+(minute|minutes|min|mins|hour|hours|hr|hrs)\b')
        .firstMatch(text);
    if (m == null) return null;
    final n = double.parse(m.group(1)!);
    if (n <= 0 || n > 10000) return null;
    final unit = m.group(2)!;
    return DateTime.now().add(unit.startsWith('min')
        ? Duration(seconds: (n * 60).round())
        : Duration(seconds: (n * 3600).round()));
  }

  static const _months = {
    'january': 1, 'jan': 1, 'february': 2, 'feb': 2, 'march': 3, 'mar': 3,
    'april': 4, 'apr': 4, 'may': 5, 'june': 6, 'jun': 6, 'july': 7, 'jul': 7,
    'august': 8, 'aug': 8, 'september': 9, 'sep': 9, 'sept': 9, 'october': 10,
    'oct': 10, 'november': 11, 'nov': 11, 'december': 12, 'dec': 12,
  };

  /// Parse "december 25", "25 december", "dec 25" → the next such date.
  static DateTime? _parseDate(String s) {
    final l = s.toLowerCase();
    int? mo, day;
    final m1 = RegExp(r'\b([a-z]+)\s+(\d{1,2})\b').firstMatch(l); // month day
    final m2 = RegExp(r'\b(\d{1,2})\s+([a-z]+)\b').firstMatch(l); // day month
    if (m1 != null && _months.containsKey(m1.group(1))) {
      mo = _months[m1.group(1)];
      day = int.tryParse(m1.group(2)!);
    } else if (m2 != null && _months.containsKey(m2.group(2))) {
      mo = _months[m2.group(2)];
      day = int.tryParse(m2.group(1)!);
    }
    if (mo == null || day == null || day < 1 || day > 31) return null;
    final now = DateTime.now();
    var d = DateTime(now.year, mo, day);
    if (d.isBefore(DateTime(now.year, now.month, now.day))) {
      d = DateTime(now.year + 1, mo, day); // next occurrence
    }
    return d;
  }

  static int _parseSeconds(String text) {
    final m = RegExp(r'(\d+(?:\.\d+)?)\s*(second|seconds|sec|minute|minutes|min|hour|hours|hr)')
        .firstMatch(text);
    if (m == null) return 0;
    final n = double.parse(m.group(1)!);
    final u = m.group(2)!;
    if (u.startsWith('sec')) return n.round();
    if (u.startsWith('hour') || u == 'hr') return (n * 3600).round();
    return (n * 60).round(); // minutes
  }

  static String _fmt(DateTime d) {
    final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ap = d.hour < 12 ? 'AM' : 'PM';
    return '$h12:${d.minute.toString().padLeft(2, '0')} $ap';
  }

  static String _clock() => _fmt(DateTime.now());

  static const _weekdays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
  ];
  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
    'September', 'October', 'November', 'December'
  ];

  /// Spoken current date from the device clock — answers year/month/day/date.
  static String _dateSpoken(String t) {
    final n = DateTime.now();
    final dow = _weekdays[n.weekday - 1];
    final mon = _monthNames[n.month - 1];
    final d = n.day;
    final suffix = (d >= 11 && d <= 13)
        ? 'th'
        : d % 10 == 1
            ? 'st'
            : d % 10 == 2
                ? 'nd'
                : d % 10 == 3
                    ? 'rd'
                    : 'th';
    if (t.contains('year')) return "It's ${n.year}.";
    if (t.contains('month')) return "It's $mon ${n.year}.";
    if (RegExp(r'\bday\b').hasMatch(t) && !t.contains('date')) {
      return "It's $dow.";
    }
    return "It's $dow, $mon $d$suffix, ${n.year}.";
  }

  // ---------- long-term memory helpers ----------
  /// Rewrite a first-person fact into second person so it reads back naturally
  /// ("i trade gold" -> "You trade gold").
  static String _asFact(String s) {
    s = s.trim();
    s = s.replaceAll(RegExp(r"^i'?m\b", caseSensitive: false), "You're");
    s = s.replaceAll(RegExp(r'^i\s+', caseSensitive: false), 'You ');
    s = s.replaceAll(RegExp(r'\bmy\b', caseSensitive: false), 'your');
    s = s.replaceAll(RegExp(r"\bi'?m\b", caseSensitive: false), "you're");
    s = s.replaceAll(RegExp(r'\bme\b', caseSensitive: false), 'you');
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  static String _titleCase(String s) => s
      .split(RegExp(r'\s+'))
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  // ---------- calculator (safe, no eval) ----------
  static String calculate(String expression) {
    var t = ' ${expression.toLowerCase()} ';
    const repl = {
      ' plus ': ' + ', ' add ': ' + ', ' minus ': ' - ', ' subtract ': ' - ',
      ' times ': ' * ', ' multiplied by ': ' * ', ' multiply by ': ' * ',
      ' divided by ': ' / ', ' over ': ' / ', ' into ': ' * ', ' x ': ' * ',
      ' power ': ' ^ ', ' to the power of ': ' ^ ',
    };
    repl.forEach((k, v) => t = t.replaceAll(k, v));
    // "X percent of Y" -> (X/100*Y)
    t = t.replaceAllMapped(
        RegExp(r'(\d+(?:\.\d+)?)\s*percent of\s*(\d+(?:\.\d+)?)'),
        (m) => '(${m[1]}/100*${m[2]})');
    t = t.replaceAll('percent', '/100');
    final cleaned = t.replaceAll(RegExp(r'[^0-9+\-*/%^().]'), ' ');
    try {
      final v = _Expr(cleaned).eval();
      final s = v == v.roundToDouble()
          ? v.round().toString()
          : v.toStringAsFixed(2);
      return 'That is $s.';
    } catch (_) {
      return "I couldn't work that out.";
    }
  }
}

/// Tiny recursive-descent arithmetic evaluator (+ - * / % ^ and parentheses).
class _Expr {
  final String s;
  int i = 0;
  _Expr(this.s);

  double eval() {
    final v = _expr();
    _ws();
    if (i < s.length) throw const FormatException('trailing');
    return v;
  }

  void _ws() {
    while (i < s.length && s[i] == ' ') {
      i++;
    }
  }

  double _expr() {
    var v = _term();
    while (true) {
      _ws();
      if (i < s.length && (s[i] == '+' || s[i] == '-')) {
        final op = s[i++];
        final r = _term();
        v = op == '+' ? v + r : v - r;
      } else {
        return v;
      }
    }
  }

  double _term() {
    var v = _factor();
    while (true) {
      _ws();
      if (i < s.length && (s[i] == '*' || s[i] == '/' || s[i] == '%')) {
        final op = s[i++];
        final r = _factor();
        v = op == '*'
            ? v * r
            : op == '/'
                ? v / r
                : v % r;
      } else {
        return v;
      }
    }
  }

  double _factor() {
    final b = _base();
    _ws();
    if (i < s.length && s[i] == '^') {
      i++;
      return _pow(b, _factor());
    }
    return b;
  }

  double _pow(double a, double b) {
    var r = 1.0;
    for (var k = 0; k < b.round().abs(); k++) {
      r *= a;
    }
    return b < 0 ? 1 / r : r;
  }

  double _base() {
    _ws();
    if (i < s.length && s[i] == '-') {
      i++;
      return -_base();
    }
    if (i < s.length && s[i] == '(') {
      i++;
      final v = _expr();
      _ws();
      if (i < s.length && s[i] == ')') i++;
      return v;
    }
    final start = i;
    while (i < s.length && RegExp(r'[0-9.]').hasMatch(s[i])) {
      i++;
    }
    if (i == start) throw const FormatException('number expected');
    return double.parse(s.substring(start, i));
  }
}
