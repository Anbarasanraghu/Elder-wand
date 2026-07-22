import 'package:flutter/material.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'theme.dart';

class AppsListScreen extends StatefulWidget {
  const AppsListScreen({super.key});

  @override
  State<AppsListScreen> createState() => _AppsListScreenState();
}

class _AppsListScreenState extends State<AppsListScreen> {
  List<AppInfo> _apps = [];
  String _filter = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final apps = await InstalledApps.getInstalledApps();
    apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    setState(() {
      _apps = apps;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final shown = _apps
        .where((a) => a.name.toLowerCase().contains(_filter.toLowerCase()))
        .toList();

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: Text('APPS · ${_apps.length}')),
      body: Container(
        decoration: const BoxDecoration(gradient: Ak.bgGradient),
        child: SafeArea(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: Ak.gold))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextField(
                        style: const TextStyle(color: Ak.textHi),
                        decoration: InputDecoration(
                          hintText: 'Search apps…',
                          hintStyle: const TextStyle(color: Ak.textLo),
                          prefixIcon:
                              const Icon(Icons.search, color: Ak.gold),
                          filled: true,
                          fillColor: Ak.glassFill,
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: Ak.glassLine),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide:
                                const BorderSide(color: Ak.gold, width: 1.5),
                          ),
                        ),
                        onChanged: (v) => setState(() => _filter = v),
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: shown.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: 8),
                        itemBuilder: (_, i) => Container(
                          decoration: Ak.glass(radius: 14),
                          child: ListTile(
                            leading: const Icon(Icons.launch,
                                color: Ak.cyan, size: 20),
                            title: Text(shown[i].name,
                                style: const TextStyle(color: Ak.textHi)),
                            subtitle: Text(shown[i].packageName,
                                style: const TextStyle(
                                    fontSize: 11, color: Ak.textLo)),
                            onTap: () =>
                                InstalledApps.startApp(shown[i].packageName),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
