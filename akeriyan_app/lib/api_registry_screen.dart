import 'package:flutter/material.dart';

import 'api_registry.dart';
import 'theme.dart';

/// Shows everything the assistant can reach — free web APIs, on-device AI, and
/// the backend — with a live count of how often each is used and when it was
/// last used. A map of the assistant's abilities, and where to grow next.
class ApiRegistryScreen extends StatelessWidget {
  const ApiRegistryScreen({super.key});

  static String _ago(DateTime? t) {
    if (t == null) return 'not yet used';
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ak.bg0,
      appBar: AppBar(
        backgroundColor: Ak.bg0,
        elevation: 0,
        title: const Text('APIs & Abilities',
            style: TextStyle(fontFamily: Ak.dot, letterSpacing: 2)),
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: ApiUsage.revision,
        builder: (context, _, _) {
          final total =
              ApiUsage.counts.values.fold<int>(0, (a, b) => a + b);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text(
                'Everything Elder Wand can tap into. Free / no-key sources are '
                'marked, and each shows how often it has been used so you can '
                'see the assistant working and decide what to add next.',
                style: TextStyle(color: Ak.textMid, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 10),
              Text('$total total API calls so far',
                  style: TextStyle(
                      color: Ak.purple,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              for (final cat in ApiRegistry.categories) ...[
                _sectionLabel(cat),
                const SizedBox(height: 8),
                for (final api in ApiRegistry.all.where((a) => a.category == cat))
                  _apiCard(api),
                const SizedBox(height: 18),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text.toUpperCase(),
        style: TextStyle(
            color: Ak.textLo,
            fontSize: 11,
            letterSpacing: 3,
            fontWeight: FontWeight.w700),
      );

  Widget _apiCard(ApiInfo api) {
    final count = ApiUsage.counts[api.id] ?? 0;
    final lastAt = ApiUsage.lastAt[api.id];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: Ak.bento(radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(api.name,
                    style: const TextStyle(
                        color: Ak.textHi,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ),
              if (count > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Ak.purple.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('$count× ',
                      style: const TextStyle(
                          color: Ak.purple,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(api.powers,
              style: TextStyle(color: Ak.textMid, fontSize: 13, height: 1.35)),
          const SizedBox(height: 10),
          Row(
            children: [
              _tag(api.onDevice ? 'On-device' : api.provider,
                  icon: api.onDevice ? Icons.smartphone : Icons.public),
              const SizedBox(width: 6),
              if (api.keyless)
                _tag('Free · no key',
                    icon: Icons.lock_open, color: Ak.green),
              const Spacer(),
              Text(_ago(lastAt),
                  style: TextStyle(color: Ak.textLo, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tag(String text, {IconData? icon, Color? color}) {
    final c = color ?? Ak.silver;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: c),
            const SizedBox(width: 4),
          ],
          Text(text,
              style: TextStyle(
                  color: c, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
