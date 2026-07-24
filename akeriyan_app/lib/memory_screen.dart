import 'package:flutter/material.dart';

import 'memory_store.dart';
import 'theme.dart';

/// Shows the permanent facts the assistant remembers about you, with the
/// ability to add or remove them by hand. Everything here is injected into the
/// on-device brain so it always knows these across restarts.
class MemoryScreen extends StatelessWidget {
  const MemoryScreen({super.key});

  Future<void> _addDialog(BuildContext context) async {
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Ak.bg2,
        title: const Text('Remember something',
            style: TextStyle(color: Ak.textHi)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Ak.textHi),
          decoration: const InputDecoration(
            hintText: 'e.g. You prefer short answers',
            hintStyle: TextStyle(color: Ak.textLo),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (text != null && text.isNotEmpty) MemoryStore.add(text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ak.bg0,
      appBar: AppBar(
        backgroundColor: Ak.bg0,
        elevation: 0,
        title: const Text('About You',
            style: TextStyle(fontFamily: Ak.dot, letterSpacing: 2)),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined, color: Ak.silver),
            tooltip: 'Forget everything',
            onPressed: () => MemoryStore.clear(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Ak.purple,
        onPressed: () => _addDialog(context),
        child: const Icon(Icons.add, color: Ak.bg0),
      ),
      body: ValueListenableBuilder<List<String>>(
        valueListenable: MemoryStore.facts,
        builder: (context, facts, _) {
          if (facts.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  "I don't know much about you yet.\n\nSay things like "
                  "\"my name is Alex\", \"I live in Chennai\", or "
                  "\"remember that I trade gold\" — and I'll keep them "
                  "forever.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Ak.textMid, height: 1.5),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            itemCount: facts.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: Ak.bento(radius: 14),
              child: Row(
                children: [
                  Icon(Icons.bookmark_border, size: 16, color: Ak.purple),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(facts[i],
                        style: const TextStyle(
                            color: Ak.textHi, fontSize: 14, height: 1.35)),
                  ),
                  GestureDetector(
                    onTap: () => MemoryStore.removeAt(i),
                    child: Icon(Icons.close, size: 16, color: Ak.textLo),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
