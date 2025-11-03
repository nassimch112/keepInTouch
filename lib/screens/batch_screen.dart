import 'package:flutter/material.dart';
import '../services/db.dart';
import '../models.dart';
import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';

class BatchScreen extends StatefulWidget {
  const BatchScreen({super.key});
  @override
  State<BatchScreen> createState() => _BatchScreenState();
}

class _BatchScreenState extends State<BatchScreen> {
  late Future<Database> _db;
  late PersonRepo _repo;
  List<Person> _due = [];

  @override
  void initState() {
    super.initState();
    _db = AppDb.instance;
    _refresh();
  }

  Future<void> _refresh() async {
    final db = await _db;
    _repo = PersonRepo(db);
    final due = await _repo.dueNow();
    setState(() => _due = due);
  }

  Future<void> _markDone(Person p) async {
    await _repo.markDone(p.id!);
    await _refresh();
  }

  Future<void> _snooze(Person p, Duration d) async {
    await _repo.snooze(p.id!, d);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        itemCount: _due.length,
        itemBuilder: (ctx, i) {
          final p = _due[i];
          return ListTile(
            title: Text(p.name),
            subtitle: Text('Every ${p.cadenceDays} days' + (p.phone != null ? ' • ${p.phone}' : '')),
            trailing: Wrap(spacing: 4, children: [
              if (p.phone != null)
                IconButton(icon: const Icon(Icons.sms), onPressed: () => launchUrl(Uri.parse('sms:${p.phone}'))),
              if (p.phone != null)
                IconButton(icon: const Icon(Icons.call), onPressed: () => launchUrl(Uri.parse('tel:${p.phone}'))),
              IconButton(icon: const Icon(Icons.snooze), onPressed: () => _snooze(p, const Duration(days: 7))),
              IconButton(icon: const Icon(Icons.check), onPressed: () => _markDone(p)),
            ]),
          );
        },
      ),
    );
  }
}
