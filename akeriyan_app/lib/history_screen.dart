import 'package:flutter/material.dart';
import 'history_store.dart';
import 'theme.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('HISTORY'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Ak.textMid),
            tooltip: 'Clear history',
            onPressed: HistoryStore.clear,
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: Ak.bgGradient),
        child: SafeArea(
          child: ValueListenableBuilder<List<ChatEntry>>(
            valueListenable: HistoryStore.entries,
            builder: (_, items, _) {
              if (items.isEmpty) {
                return const Center(
                  child: Text('Nothing yet.\nSay "Hey Elder Wand" to start.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Ak.textLo, fontSize: 15)),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, i) => _entryCard(items[i]),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _entryCard(ChatEntry e) {
    final t = e.at;
    final time =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: Ak.glass(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person, size: 15, color: Ak.textLo),
              const SizedBox(width: 8),
              Expanded(
                child: Text('"${e.youSaid}"',
                    style: const TextStyle(
                        color: Ak.textHi, fontWeight: FontWeight.w500)),
              ),
              Text(time,
                  style: const TextStyle(fontSize: 11, color: Ak.textLo)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: const BoxDecoration(
                    gradient: Ak.goldGradient, shape: BoxShape.circle),
                child: const Icon(Icons.auto_awesome, size: 12, color: Ak.bg0),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    e.akeriyanSaid.isEmpty
                        ? '(action performed)'
                        : e.akeriyanSaid,
                    style: const TextStyle(color: Ak.gold, height: 1.35)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: Ak.glassFillStrong,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(e.intent,
                style: const TextStyle(fontSize: 10, color: Ak.cyan)),
          ),
        ],
      ),
    );
  }
}
