import 'package:flutter/material.dart';

import 'theme.dart';
import 'personal_store.dart';

/// Visual view of the on-device personal data you build by voice:
/// to-do, notes, journal, habits, expenses and countdowns.
class PersonalScreen extends StatefulWidget {
  const PersonalScreen({super.key});

  @override
  State<PersonalScreen> createState() => _PersonalScreenState();
}

class _PersonalScreenState extends State<PersonalScreen> {
  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('MY DATA'),
          bottom: const TabBar(
            isScrollable: true,
            labelColor: Ak.gold,
            unselectedLabelColor: Ak.textMid,
            indicatorColor: Ak.gold,
            tabs: [
              Tab(text: 'To-Do'),
              Tab(text: 'Notes'),
              Tab(text: 'Journal'),
              Tab(text: 'Habits'),
              Tab(text: 'Expenses'),
              Tab(text: 'Countdowns'),
            ],
          ),
        ),
        body: Stack(
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(gradient: Ak.bgGradient),
              child: SizedBox.expand(),
            ),
            Positioned.fill(child: Ak.ambientGlow()),
            SafeArea(
              top: false,
              child: TabBarView(
                children: [
                  _todoTab(),
                  _simpleTab(PersonalStore.kNotes, 't', 'No notes yet.',
                      "Say: “take a note …”"),
                  _simpleTab(PersonalStore.kJournal, 't', 'Journal is empty.',
                      "Say: “journal: today …”"),
                  _habitsTab(),
                  _expensesTab(),
                  _eventsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty(String msg, String hint) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(msg, style: const TextStyle(color: Ak.textMid, fontSize: 15)),
              const SizedBox(height: 8),
              Text(hint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Ak.textLo, fontSize: 13)),
            ],
          ),
        ),
      );

  Widget _card({required Widget child, VoidCallback? onDelete}) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: Ak.bento(radius: 14),
        child: Row(
          children: [
            Expanded(child: child),
            if (onDelete != null)
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: Ak.textLo),
                onPressed: onDelete,
              ),
          ],
        ),
      );

  // ---- To-Do ----
  Widget _todoTab() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: PersonalStore.items(PersonalStore.kTodo),
      builder: (_, snap) {
        final items = snap.data ?? [];
        if (items.isEmpty) {
          return _empty('Your list is empty.', 'Say: “add milk to my list”');
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          itemBuilder: (_, i) {
            final done = items[i]['done'] == true;
            return _card(
              onDelete: () async {
                await PersonalStore.removeItem(PersonalStore.kTodo, i);
                _refresh();
              },
              child: InkWell(
                onTap: () async {
                  await PersonalStore.toggleTodo(i);
                  _refresh();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Icon(
                          done
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          size: 20,
                          color: done ? Ak.green : Ak.textMid),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${items[i]['t']}',
                          style: TextStyle(
                            color: done ? Ak.textLo : Ak.textHi,
                            decoration:
                                done ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ---- simple text list (notes, journal) ----
  Widget _simpleTab(String key, String field, String empty, String hint) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: PersonalStore.items(key),
      builder: (_, snap) {
        final items = snap.data ?? [];
        if (items.isEmpty) return _empty(empty, hint);
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          itemBuilder: (_, i) => _card(
            onDelete: () async {
              await PersonalStore.removeItem(key, i);
              _refresh();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('${items[i][field]}',
                  style: const TextStyle(color: Ak.textHi, height: 1.4)),
            ),
          ),
        );
      },
    );
  }

  // ---- Habits ----
  Widget _habitsTab() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: PersonalStore.items(PersonalStore.kHabits),
      builder: (_, snap) {
        final items = snap.data ?? [];
        if (items.isEmpty) {
          return _empty('No habits tracked.', 'Say: “log exercise habit”');
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          itemBuilder: (_, i) {
            final streak = PersonalStore.habitStreak(items[i]);
            return _card(
              onDelete: () async {
                await PersonalStore.removeItem(PersonalStore.kHabits, i);
                _refresh();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.local_fire_department,
                        size: 20, color: Ak.gold),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text('${items[i]['n']}',
                            style: const TextStyle(color: Ak.textHi))),
                    Text('$streak day streak',
                        style: const TextStyle(color: Ak.gold, fontSize: 12)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ---- Expenses ----
  Widget _expensesTab() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: PersonalStore.items(PersonalStore.kExpenses),
      builder: (_, snap) {
        final items = snap.data ?? [];
        if (items.isEmpty) {
          return _empty('No expenses logged.', 'Say: “I spent 200 on lunch”');
        }
        final total = items.fold<double>(
            0, (s, e) => s + (e['a'] as num).toDouble());
        return Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              padding: const EdgeInsets.all(16),
              decoration: Ak.bento(glow: true),
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('TOTAL',
                      style: TextStyle(color: Ak.textMid, fontSize: 11)),
                  const SizedBox(height: 4),
                  Text('${total.round()}',
                      style: const TextStyle(
                          color: Ak.textHi,
                          fontSize: 30,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                itemBuilder: (_, i) => _card(
                  onDelete: () async {
                    await PersonalStore.removeItem(PersonalStore.kExpenses, i);
                    _refresh();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                            child: Text('${items[i]['c']}',
                                style: const TextStyle(color: Ak.textHi))),
                        Text('${(items[i]['a'] as num).round()}',
                            style: const TextStyle(
                                color: Ak.textHi,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ---- Countdowns ----
  Widget _eventsTab() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: PersonalStore.items(PersonalStore.kEvents),
      builder: (_, snap) {
        final items = snap.data ?? [];
        if (items.isEmpty) {
          return _empty('No countdowns.', 'Say: “my birthday is on December 25”');
        }
        final now = DateTime.now();
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          itemBuilder: (_, i) {
            final d = DateTime.tryParse('${items[i]['d']}');
            final days =
                d?.difference(DateTime(now.year, now.month, now.day)).inDays;
            return _card(
              onDelete: () async {
                await PersonalStore.removeItem(PersonalStore.kEvents, i);
                _refresh();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                        child: Text('${items[i]['n']}',
                            style: const TextStyle(color: Ak.textHi))),
                    Text(days == null ? '—' : '$days days',
                        style: const TextStyle(color: Ak.gold, fontSize: 13)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
