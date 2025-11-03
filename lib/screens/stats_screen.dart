import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart' as sql;
import '../services/db.dart';
import '../models.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});
  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  String _range = '90d'; // all, 365d, 90d, 30d
  late Future<AppData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<AppData> _load() async {
    final db = await AppDb.instance;
    final now = DateTime.now();
    int? cutoff;
    switch (_range) {
      case 'all':
        cutoff = null;
        break;
      case '365d':
        cutoff = now.subtract(const Duration(days: 365)).millisecondsSinceEpoch;
        break;
      case '30d':
        cutoff = now.subtract(const Duration(days: 30)).millisecondsSinceEpoch;
        break;
      case '90d':
      default:
        cutoff = now.subtract(const Duration(days: 90)).millisecondsSinceEpoch;
        break;
    }

    // Overall counts
    final where = cutoff == null ? '' : 'WHERE at >= ?';
    final whereArgs = cutoff == null ? <Object?>[] : [cutoff];
  final total = sql.Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM interaction $where', whereArgs)) ?? 0;
  final mine = sql.Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM interaction $where ${where.isEmpty ? 'WHERE' : 'AND'} initiator='me'", whereArgs)) ?? 0;
    final theirs = total - mine;

    // Per-person leaderboard
    final rows = await db.rawQuery('''
      SELECT i.personId AS pid,
             COUNT(*) AS cnt,
             SUM(CASE WHEN initiator='me' THEN 1 ELSE 0 END) AS mine,
             SUM(CASE WHEN initiator!='me' THEN 1 ELSE 0 END) AS theirs,
             MAX(at) AS lastAt
      FROM interaction i
      ${where}
      GROUP BY i.personId
      ORDER BY cnt DESC, lastAt DESC
      LIMIT 50
    ''', whereArgs);

    // Fetch names for people
    final leaderboard = <PersonStats>[];
    for (final r in rows) {
      final pid = r['pid'] as int?;
      if (pid == null) continue;
      final personRows = await db.query('person', where: 'id=?', whereArgs: [pid]);
      if (personRows.isEmpty) continue;
      final person = PersonMap.fromMap(personRows.first);
      leaderboard.add(PersonStats(
        person: person,
        count: (r['cnt'] as int?) ?? 0,
        mine: (r['mine'] as int?) ?? 0,
        theirs: (r['theirs'] as int?) ?? 0,
        lastAt: (r['lastAt'] as int?) != null ? DateTime.fromMillisecondsSinceEpoch(r['lastAt'] as int) : null,
      ));
    }

    return AppData(total: total, mine: mine, theirs: theirs, leaderboard: leaderboard);
  }

  void _setRange(String r) {
    setState(() {
      _range = r;
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppData>(
      future: _future,
      builder: (context, snap) {
        final data = snap.data;
        return SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
            children: [
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(label: const Text('All time'), selected: _range=='all', onSelected: (_) => _setRange('all')),
                  ChoiceChip(label: const Text('365 days'), selected: _range=='365d', onSelected: (_) => _setRange('365d')),
                  ChoiceChip(label: const Text('90 days'), selected: _range=='90d', onSelected: (_) => _setRange('90d')),
                  ChoiceChip(label: const Text('30 days'), selected: _range=='30d', onSelected: (_) => _setRange('30d')),
                ],
              ),
              const SizedBox(height: 12),
              if (data != null) ...[
                _overallCard(data),
                const SizedBox(height: 12),
                _leaderboardCard(data),
              ] else ...[
                const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _overallCard(AppData d) {
    final total = d.total;
    final minePct = total == 0 ? 0 : (d.mine * 100 ~/ total);
    final theirsPct = total == 0 ? 0 : (d.theirs * 100 ~/ total);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Overall', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                _metric('Interactions', total.toString()),
                const SizedBox(width: 16),
                _metric('I initiated', '${d.mine} ($minePct%)'),
                const SizedBox(width: 16),
                _metric('They initiated', '${d.theirs} (${theirsPct}%)'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _leaderboardCard(AppData d) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Top people', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...d.leaderboard.map(_personRow),
          ],
        ),
      ),
    );
  }

  Widget _personRow(PersonStats ps) {
    final last = ps.lastAt != null ? DateFormat('MMM d, yyyy').format(ps.lastAt!) : '—';
    final total = ps.count;
    final minePct = total == 0 ? 0 : (ps.mine * 100 ~/ total);
    return ListTile(
      leading: CircleAvatar(child: Text(ps.person.name.isNotEmpty ? ps.person.name[0].toUpperCase() : '?')),
      title: Text(ps.person.name),
  subtitle: Text('Total: $total • I: ${ps.mine} ($minePct%) • Last: $last'),
      onTap: () => _showPersonBreakdown(ps),
    );
  }

  void _showPersonBreakdown(PersonStats ps) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(ps.person.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('Total interactions: ${ps.count}'),
              Text('I initiated: ${ps.mine}'),
              Text('They initiated: ${ps.theirs}'),
              if (ps.lastAt != null) Text('Last interaction: ${DateFormat('MMM d, yyyy').format(ps.lastAt!)}'),
              const SizedBox(height: 12),
              const Text('Ideas to add next:'),
              const SizedBox(height: 6),
              const Text('• Response time (avg days between interactions)'),
              const Text('• Streaks / longest gap'),
              const Text('• Distribution by day of week / hour'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class AppData {
  final int total;
  final int mine;
  final int theirs;
  final List<PersonStats> leaderboard;
  AppData({required this.total, required this.mine, required this.theirs, required this.leaderboard});
}

class PersonStats {
  final Person person;
  final int count;
  final int mine;
  final int theirs;
  final DateTime? lastAt;
  PersonStats({required this.person, required this.count, required this.mine, required this.theirs, required this.lastAt});
}
