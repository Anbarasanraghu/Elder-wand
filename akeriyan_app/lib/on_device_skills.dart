import 'dart:convert';

import 'package:http/http.dart' as http;

/// Weather / news / web-search answered ENTIRELY on the phone by calling the
/// same free, no-key public APIs the backend used (Open-Meteo, Google News RSS,
/// DuckDuckGo). No PC, no backend needed for these.
class OnDeviceSkills {
  static final _weather = RegExp(
      r'\b(weather|temperature|forecast|how (hot|cold|warm)|will it rain|raining|humidity)\b',
      caseSensitive: false);
  static final _news = RegExp(
      r"\b(news|headlines|what'?s happening|latest (news|updates))\b",
      caseSensitive: false);
  static final _search = RegExp(
      r'\b(search (for )?|look ?up|google|find (me )?(info|information) (on|about))\b',
      caseSensitive: false);

  /// If [text] is a weather/news/search request, answer it on-device and return
  /// the spoken reply. Returns null if it isn't one of these (let Gemma/backend
  /// handle it).
  static Future<String?> respond(String text,
      {double? lat, double? lon}) async {
    if (_weather.hasMatch(text)) {
      return weather(city: _cityFrom(text), lat: lat, lon: lon);
    }
    if (_news.hasMatch(text)) {
      return news(topic: _topicFrom(text));
    }
    final m = _search.firstMatch(text);
    if (m != null) {
      final q = text.substring(m.end).trim();
      if (q.isNotEmpty) return search(q);
    }
    return null;
  }

  // ---- helpers to pull a city / topic out of the sentence ----
  static String? _cityFrom(String t) {
    final m = RegExp(r'\b(?:in|at|for)\s+([a-zA-Z][a-zA-Z .\-]{1,40})',
            caseSensitive: false)
        .firstMatch(t);
    return m?.group(1)?.trim();
  }

  static String? _topicFrom(String t) {
    final m = RegExp(r'\b(?:about|on|for)\s+([a-zA-Z][a-zA-Z0-9 .\-]{1,50})',
            caseSensitive: false)
        .firstMatch(t);
    return m?.group(1)?.trim();
  }

  // ---- Weather (Open-Meteo, free) ----
  static const _wxCodes = {
    0: 'clear sky', 1: 'mainly clear', 2: 'partly cloudy', 3: 'overcast',
    45: 'foggy', 48: 'rime fog', 51: 'light drizzle', 53: 'drizzle',
    55: 'heavy drizzle', 61: 'light rain', 63: 'rain', 65: 'heavy rain',
    71: 'light snow', 73: 'snow', 75: 'heavy snow', 80: 'rain showers',
    81: 'rain showers', 82: 'violent rain showers', 95: 'a thunderstorm',
    96: 'a thunderstorm with hail', 99: 'a severe thunderstorm',
  };

  static Future<String> weather(
      {String? city, double? lat, double? lon}) async {
    try {
      String place;
      if ((city == null || city.isEmpty) && lat != null && lon != null) {
        place = await _reversePlace(lat, lon) ?? 'your location';
      } else {
        city = (city == null || city.isEmpty) ? 'Chennai' : city;
        final geo = await _getJson(
            'https://geocoding-api.open-meteo.com/v1/search?name=${Uri.encodeQueryComponent(city)}&count=1&language=en');
        final results = geo?['results'] as List?;
        if (results == null || results.isEmpty) {
          return "I couldn't find a place called $city.";
        }
        final loc = results.first as Map;
        lat = (loc['latitude'] as num).toDouble();
        lon = (loc['longitude'] as num).toDouble();
        place = '${loc['name'] ?? city}';
      }
      final wx = await _getJson(
          'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon'
          '&current=temperature_2m,apparent_temperature,weather_code'
          '&daily=temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=1');
      final cur = wx?['current'] as Map?;
      final daily = wx?['daily'] as Map?;
      if (cur == null || daily == null) {
        return "I couldn't reach the weather service right now.";
      }
      final desc = _wxCodes[cur['weather_code']] ?? 'unclear skies';
      final temp = (cur['temperature_2m'] as num).round();
      final feels = (cur['apparent_temperature'] as num).round();
      final hi = ((daily['temperature_2m_max'] as List).first as num).round();
      final lo = ((daily['temperature_2m_min'] as List).first as num).round();
      return "In $place it's $temp degrees with $desc, feels like $feels. "
          "Today's high is $hi and low is $lo.";
    } catch (_) {
      return "I couldn't reach the weather service right now.";
    }
  }

  static Future<String?> _reversePlace(double lat, double lon) async {
    final j = await _getJson(
        'https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=$lat&longitude=$lon&localityLanguage=en');
    if (j == null) return null;
    return (j['city'] ?? j['locality'] ?? j['principalSubdivision'] ??
            j['countryName']) as String?;
  }

  // ---- News (Google News RSS, free) ----
  static Future<String> news({String? topic, int limit = 4}) async {
    try {
      final url = (topic != null && topic.isNotEmpty)
          ? 'https://news.google.com/rss/search?q=${Uri.encodeQueryComponent(topic)}&hl=en-IN&gl=IN&ceid=IN:en'
          : 'https://news.google.com/rss?hl=en-IN&gl=IN&ceid=IN:en';
      final resp = await http.get(Uri.parse(url)).timeout(_t);
      if (resp.statusCode != 200) {
        return "I couldn't reach the news service right now.";
      }
      final titles = RegExp(r'<title>(.*?)</title>', dotAll: true)
          .allMatches(resp.body)
          .map((m) => m.group(1) ?? '')
          .skip(1) // first <title> is the feed name
          .map(_cleanTitle)
          .where((t) => t.isNotEmpty)
          .take(limit)
          .toList();
      if (titles.isEmpty) return "I couldn't find any headlines right now.";
      final lead = (topic != null && topic.isNotEmpty)
          ? 'Top news about $topic: '
          : 'Here are the top headlines: ';
      return lead +
          [for (var i = 0; i < titles.length; i++) '${i + 1}. ${titles[i]}']
              .join(' ... ');
    } catch (_) {
      return "I couldn't reach the news service right now.";
    }
  }

  static String _cleanTitle(String t) {
    t = t.replaceAll(RegExp(r'<!\[CDATA\[(.*?)\]\]>', dotAll: true), r'$1');
    t = _unescape(t).trim();
    t = t.replaceAll(RegExp(r'\s+-\s+[^-]+$'), ''); // drop " - Publisher"
    return t;
  }

  // ---- Web search (DuckDuckGo Instant Answer, free) ----
  static Future<String> search(String query) async {
    query = query.trim();
    if (query.isEmpty) return 'What would you like me to look up?';
    try {
      final d = await _getJson(
          'https://api.duckduckgo.com/?q=${Uri.encodeQueryComponent(query)}&format=json&no_html=1&skip_disambig=1');
      String? answer = (d?['AbstractText'] as String?)?.trim();
      if (answer == null || answer.isEmpty) {
        answer = (d?['Answer'] as String?)?.trim();
      }
      if (answer == null || answer.isEmpty) {
        final topics = d?['RelatedTopics'] as List?;
        if (topics != null) {
          for (final tp in topics) {
            if (tp is Map && (tp['Text'] as String?)?.isNotEmpty == true) {
              answer = tp['Text'] as String;
              break;
            }
          }
        }
      }
      if (answer != null && answer.isNotEmpty) {
        final parts = answer.replaceAll('\n', ' ').split('. ');
        return '${parts.take(2).join('. ').trim().replaceAll(RegExp(r'\.$'), '')}.';
      }
    } catch (_) {}
    return "I couldn't find a quick answer for that.";
  }

  // ---- crypto price (CoinGecko, free, no key) ----
  static const _coins = {
    'bitcoin': 'bitcoin', 'btc': 'bitcoin', 'ethereum': 'ethereum',
    'eth': 'ethereum', 'solana': 'solana', 'sol': 'solana',
    'dogecoin': 'dogecoin', 'doge': 'dogecoin', 'cardano': 'cardano',
    'ada': 'cardano', 'ripple': 'ripple', 'xrp': 'ripple',
    'binance coin': 'binancecoin', 'bnb': 'binancecoin',
    'litecoin': 'litecoin', 'ltc': 'litecoin', 'polkadot': 'polkadot',
    'chainlink': 'chainlink', 'avalanche': 'avalanche-2',
  };

  static Future<String> cryptoPrice(String coin) async {
    final key = coin.toLowerCase().trim();
    final id = _coins[key] ?? key.replaceAll(' ', '-');
    final j = await _getJson(
        'https://api.coingecko.com/api/v3/simple/price?ids=$id&vs_currencies=usd,inr&include_24hr_change=true');
    final d = j?[id] as Map?;
    if (d == null) return "I couldn't find a price for $coin.";
    final usd = (d['usd'] as num?)?.round();
    final inr = (d['inr'] as num?)?.round();
    final chg = (d['usd_24h_change'] as num?);
    final trend = chg == null
        ? ''
        : ', ${chg < 0 ? 'down' : 'up'} ${chg.abs().toStringAsFixed(1)} percent today';
    return '$coin is $usd dollars${inr != null ? ', about $inr rupees' : ''}$trend.';
  }

  // ---- currency (open.er-api.com, free, no key) ----
  static const _curNames = {
    'USD': 'dollars', 'INR': 'rupees', 'EUR': 'euros', 'GBP': 'pounds',
    'JPY': 'yen', 'AUD': 'Australian dollars', 'CAD': 'Canadian dollars',
  };

  static String curCode(String w) {
    w = w.toLowerCase().trim();
    if (w.startsWith('dollar') || w.startsWith('buck')) return 'USD';
    if (w.startsWith('rupee') || w == 'rs') return 'INR';
    if (w.startsWith('euro')) return 'EUR';
    if (w.startsWith('pound')) return 'GBP';
    if (w == 'yen') return 'JPY';
    return w.toUpperCase();
  }

  static String _curName(String code) => _curNames[code] ?? code;

  static Future<String> currencyConvert(
      double amount, String from, String to) async {
    from = curCode(from);
    to = curCode(to);
    final j = await _getJson('https://open.er-api.com/v6/latest/$from');
    final rate = (j?['rates'] as Map?)?[to] as num?;
    if (rate == null) return "I couldn't get that exchange rate.";
    final result = (amount * rate).round();
    return '${amount.round()} ${_curName(from)} is $result ${_curName(to)}.';
  }

  static Future<String> currencyRate(String from, String to) async {
    from = curCode(from);
    to = curCode(to);
    final j = await _getJson('https://open.er-api.com/v6/latest/$from');
    final rate = (j?['rates'] as Map?)?[to] as num?;
    if (rate == null) return "I couldn't get that exchange rate.";
    return 'One ${_curName(from).replaceAll('s', '')} is ${rate.toStringAsFixed(2)} ${_curName(to)}.';
  }

  // ---- shared ----
  static const _t = Duration(seconds: 10);

  static Future<Map<String, dynamic>?> _getJson(String url) async {
    try {
      final r = await http.get(Uri.parse(url)).timeout(_t);
      if (r.statusCode != 200) return null;
      return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static String _unescape(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'");
}
