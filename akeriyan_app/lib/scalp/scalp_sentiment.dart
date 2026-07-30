import 'package:http/http.dart' as http;

/// News-based market bias for the instrument — scrapes recent headlines
/// (Google News, free) and scores bullish/bearish tone. This is a sentiment
/// GAUGE, not a prediction of what the market will do.
class Sentiment {
  final double score; // -1..1
  final String label; // Bullish / Bearish / Neutral
  final List<String> headlines;
  Sentiment(this.score, this.label, this.headlines);
}

class NewsSentiment {
  static const _bull = [
    'surge', 'rally', 'gain', 'gains', 'rise', 'rises', 'jump', 'bullish',
    'soar', 'climb', 'boost', 'higher', 'record', 'strong', 'beat', 'optimism',
    'recovery', 'rebound', 'upside', 'demand', 'safe-haven', 'buy'
  ];
  static const _bear = [
    'fall', 'falls', 'drop', 'drops', 'plunge', 'decline', 'bearish', 'slump',
    'crash', 'lower', 'weak', 'weaker', 'loss', 'losses', 'fear', 'recession',
    'cut', 'cuts', 'miss', 'sell-off', 'selloff', 'tumble', 'pressure', 'sell'
  ];

  static String _query(String symbol) {
    if (symbol.startsWith('XAU')) return 'gold price';
    if (symbol.startsWith('XAG')) return 'silver price';
    if (symbol.startsWith('BTC')) return 'bitcoin price';
    return '${symbol.replaceAll('/', ' ')} forex';
  }

  static Future<Sentiment> forSymbol(String symbol) async {
    try {
      final url = 'https://news.google.com/rss/search?q='
          '${Uri.encodeQueryComponent(_query(symbol))}&hl=en-US&gl=US&ceid=US:en';
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      final titles = RegExp(r'<title>(.*?)</title>', dotAll: true)
          .allMatches(r.body)
          .map((m) => (m.group(1) ?? '')
              .replaceAll(RegExp(r'<!\[CDATA\[(.*?)\]\]>', dotAll: true), r'$1')
              .trim())
          .skip(1)
          .where((t) => t.isNotEmpty)
          .take(8)
          .toList();
      var score = 0;
      for (final t in titles) {
        final l = t.toLowerCase();
        for (final w in _bull) {
          if (l.contains(w)) score++;
        }
        for (final w in _bear) {
          if (l.contains(w)) score--;
        }
      }
      final norm = titles.isEmpty ? 0.0 : (score / titles.length).clamp(-1, 1);
      final label = norm > 0.15 ? 'Bullish' : norm < -0.15 ? 'Bearish' : 'Neutral';
      return Sentiment(norm.toDouble(), label, titles);
    } catch (_) {
      return Sentiment(0, 'Neutral', const []);
    }
  }
}
