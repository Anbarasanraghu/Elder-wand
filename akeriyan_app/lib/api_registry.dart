import 'package:flutter/foundation.dart';

import 'local_cache.dart';

/// A single capability the assistant can reach — a free web API, an on-device
/// model, or the user's own backend. This is the master list the API page shows
/// so we can see (and grow) exactly what Elder Wand is able to do.
class ApiInfo {
  final String id;
  final String name;
  final String provider;
  final String category; // one of ApiRegistry.categories
  final String powers; // what feature(s) it drives, in plain words
  final bool keyless; // true = free, no API key needed
  final bool onDevice; // true = runs on the phone, no network
  final String? url; // base endpoint / home, for reference

  const ApiInfo({
    required this.id,
    required this.name,
    required this.provider,
    required this.category,
    required this.powers,
    this.keyless = true,
    this.onDevice = false,
    this.url,
  });
}

/// The master catalog. Add a row here whenever the assistant gains a new
/// source, and call [ApiUsage.record] with the matching id where it's used.
class ApiRegistry {
  static const catWeb = 'Free web APIs';
  static const catDevice = 'On-device AI';
  static const catBackend = 'Your backend';
  static const categories = [catWeb, catDevice, catBackend];

  static const List<ApiInfo> all = [
    // ---- free, no-key web APIs ----
    ApiInfo(
      id: 'open-meteo',
      name: 'Open-Meteo',
      provider: 'open-meteo.com',
      category: catWeb,
      powers: 'Live weather, forecast & city geocoding',
      url: 'https://api.open-meteo.com',
    ),
    ApiInfo(
      id: 'bigdatacloud',
      name: 'BigDataCloud Reverse Geocode',
      provider: 'bigdatacloud.net',
      category: catWeb,
      powers: 'Turns your GPS into a place name for weather',
      url: 'https://api.bigdatacloud.net',
    ),
    ApiInfo(
      id: 'google-news',
      name: 'Google News RSS',
      provider: 'news.google.com',
      category: catWeb,
      powers: 'Top headlines & topic news',
      url: 'https://news.google.com/rss',
    ),
    ApiInfo(
      id: 'duckduckgo',
      name: 'DuckDuckGo Instant Answer',
      provider: 'duckduckgo.com',
      category: catWeb,
      powers: 'Quick web lookups & facts',
      url: 'https://api.duckduckgo.com',
    ),
    ApiInfo(
      id: 'coingecko',
      name: 'CoinGecko',
      provider: 'coingecko.com',
      category: catWeb,
      powers: 'Live crypto prices (BTC, ETH, …)',
      url: 'https://api.coingecko.com',
    ),
    ApiInfo(
      id: 'er-api',
      name: 'Exchange Rate API',
      provider: 'open.er-api.com',
      category: catWeb,
      powers: 'Currency conversion & live FX rates',
      url: 'https://open.er-api.com',
    ),
    // ---- on-device AI ----
    ApiInfo(
      id: 'gemma',
      name: 'Gemma (LiteRT-LM)',
      provider: 'On your phone',
      category: catDevice,
      onDevice: true,
      powers: 'The conversational brain — chat, Q&A, explanations',
    ),
    ApiInfo(
      id: 'stt',
      name: 'Speech-to-Text',
      provider: 'On your phone',
      category: catDevice,
      onDevice: true,
      powers: 'Turns your voice into text',
    ),
    ApiInfo(
      id: 'tts',
      name: 'Text-to-Speech',
      provider: 'On your phone',
      category: catDevice,
      onDevice: true,
      powers: 'Speaks replies in a natural voice',
    ),
    ApiInfo(
      id: 'wakeword',
      name: 'Wake-word (Vosk)',
      provider: 'On your phone',
      category: catDevice,
      onDevice: true,
      powers: 'Always-on "Hey Elder Wand" listening',
    ),
    ApiInfo(
      id: 'intents',
      name: 'Android System Actions',
      provider: 'On your phone',
      category: catDevice,
      onDevice: true,
      powers: 'Alarms, timers, calendar events, music',
    ),
    ApiInfo(
      id: 'mlkit-ocr',
      name: 'ML Kit OCR',
      provider: 'On your phone',
      category: catDevice,
      onDevice: true,
      powers: 'Reads text from the camera (document scan)',
    ),
    ApiInfo(
      id: 'qr-scanner',
      name: 'QR / Barcode Scanner',
      provider: 'On your phone',
      category: catDevice,
      onDevice: true,
      powers: 'Scans QR codes & barcodes',
    ),
    // ---- your own backend ----
    ApiInfo(
      id: 'backend',
      name: 'Elder Wand Server',
      provider: 'Self-hosted (free)',
      category: catBackend,
      powers: 'Trading analysis, email, CRM & heavier skills',
    ),
  ];

  static ApiInfo? byId(String id) {
    for (final a in all) {
      if (a.id == id) return a;
    }
    return null;
  }
}

/// A single "this API was just used" event, for the live "via …" chip.
class ApiHit {
  final String id;
  final String name;
  final DateTime at;
  const ApiHit(this.id, this.name, this.at);
}

/// Tracks which APIs the assistant actually uses — a running count + last-used
/// time per source (shown on the API page) and the most recent hit (shown as a
/// live "via …" chip under the reply). Persisted so history survives restarts.
class ApiUsage {
  /// Most recent API hit of the CURRENT turn, or null. The assistant clears
  /// this at the start of a turn and it's set the moment a source is called.
  static final ValueNotifier<ApiHit?> last = ValueNotifier<ApiHit?>(null);

  /// Bumps whenever counts change, so the API page can rebuild live.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static final Map<String, int> counts = {};
  static final Map<String, DateTime> lastAt = {};
  static bool _loaded = false;

  /// Load saved usage from disk. Call once at startup.
  static Future<void> init() async {
    if (_loaded) return;
    _loaded = true;
    final data = await LocalCache.load('api_usage');
    if (data is Map) {
      final c = data['counts'];
      final l = data['lastAt'];
      if (c is Map) {
        c.forEach((k, v) {
          if (v is int) counts['$k'] = v;
        });
      }
      if (l is Map) {
        l.forEach((k, v) {
          final t = DateTime.tryParse('$v');
          if (t != null) lastAt['$k'] = t;
        });
      }
      revision.value++;
    }
  }

  /// Record one use of the source [id]. Safe to call from any skill.
  /// [live] updates the "via …" chip; pass false for plumbing like TTS/STT so
  /// they still count but don't hide the real data source in the chip.
  static void record(String id, {bool live = true}) {
    final now = DateTime.now();
    counts[id] = (counts[id] ?? 0) + 1;
    lastAt[id] = now;
    if (live) last.value = ApiHit(id, ApiRegistry.byId(id)?.name ?? id, now);
    revision.value++;
    _persist();
  }

  /// Clear the live "via …" chip at the start of a new turn.
  static void clearLast() => last.value = null;

  static void _persist() => LocalCache.save('api_usage', {
        'counts': counts,
        'lastAt': lastAt.map((k, v) => MapEntry(k, v.toIso8601String())),
      });
}
