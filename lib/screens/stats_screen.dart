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
  late Future<Insights> _insightsFuture;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _insightsFuture = _loadInsights();
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

    final where = cutoff == null ? '' : 'WHERE at >= ?';
    final whereArgs = cutoff == null ? <Object?>[] : [cutoff];

    final total = sql.Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM interaction $where', whereArgs),
        ) ??
        0;
    final mine = sql.Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COUNT(*) FROM interaction $where ${where.isEmpty ? 'WHERE' : 'AND'} initiator='me'",
            whereArgs,
          ),
        ) ??
        0;
    final theirs = total - mine;

    final rows = await db.rawQuery('''
      SELECT i.personId AS pid,
             COUNT(*) AS cnt,
             SUM(CASE WHEN initiator='me' THEN 1 ELSE 0 END) AS mine,
             SUM(CASE WHEN initiator!='me' THEN 1 ELSE 0 END) AS theirs,
             MAX(at) AS lastAt
      FROM interaction i
      $where
      GROUP BY i.personId
      ORDER BY cnt DESC, lastAt DESC
      LIMIT 50
    ''', whereArgs);

    final leaderboard = <PersonStats>[];
    for (final r in rows) {
      final pid = r['pid'] as int?;
      if (pid == null) continue;
      final personRows = await db.query('person', where: 'id=?', whereArgs: [pid]);
      if (personRows.isEmpty) continue;
      final person = PersonMap.fromMap(personRows.first);
      leaderboard.add(
        PersonStats(
          person: person,
          count: (r['cnt'] as int?) ?? 0,
          mine: (r['mine'] as int?) ?? 0,
          theirs: (r['theirs'] as int?) ?? 0,
          lastAt: (r['lastAt'] as int?) != null
              ? DateTime.fromMillisecondsSinceEpoch(r['lastAt'] as int)
              : null,
        ),
      );
    }

    return AppData(total: total, mine: mine, theirs: theirs, leaderboard: leaderboard);
  }

  Future<Insights> _loadInsights() async {
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

    final where = cutoff == null ? '' : 'WHERE at >= ?';
    final whereArgs = cutoff == null ? <Object?>[] : [cutoff];
    final rows = await db.rawQuery('SELECT at FROM interaction $where ORDER BY at ASC', whereArgs);

    final times = <DateTime>[];
    for (final r in rows) {
      final at = r['at'] as int?;
      if (at != null) times.add(DateTime.fromMillisecondsSinceEpoch(at));
    }

    final dowCounts = List<int>.filled(7, 0);
    final hourCounts = List<int>.filled(24, 0);
    for (final t in times) {
      final dow = t.weekday - 1; // Mon=1..Sun=7 -> 0..6
      if (dow >= 0 && dow < 7) dowCounts[dow]++;
      final h = t.hour;
      if (h >= 0 && h < 24) hourCounts[h]++;
    }

    double avgGapDays = double.nan;
    int longestGapDays = 0;
    if (times.length >= 2) {
      int gaps = 0;
      int gapsCount = 0;
      for (var i = 1; i < times.length; i++) {
        final d = times[i].difference(times[i - 1]).inDays;
        gaps += d;
        gapsCount++;
        if (d > longestGapDays) longestGapDays = d;
      }
      if (gapsCount > 0) avgGapDays = gaps / gapsCount;
    }

    int longestStreakDays = 0;
    if (times.isNotEmpty) {
      final dates = <DateTime>[];
      DateTime? lastDate;
      for (final t in times) {
        final d = DateTime(t.year, t.month, t.day);
        if (lastDate == null || d.difference(lastDate).inDays != 0) {
          dates.add(d);
          lastDate = d;
        }
      }
      int cur = dates.isEmpty ? 0 : 1;
      longestStreakDays = cur;
      for (var i = 1; i < dates.length; i++) {
        if (dates[i].difference(dates[i - 1]).inDays == 1) {
          cur++;
        } else {
          if (cur > longestStreakDays) longestStreakDays = cur;
          cur = 1;
        }
      }
      if (cur > longestStreakDays) longestStreakDays = cur;
    }

    return Insights(
      avgGapDays: avgGapDays,
      longestStreakDays: longestStreakDays,
      longestGapDays: longestGapDays,
      dowCounts: dowCounts,
      hourCounts: hourCounts,
    );
  }

  void _setRange(String r) {
    setState(() {
      _range = r;
      _future = _load();
      _insightsFuture = _loadInsights();
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
                  ChoiceChip(label: const Text('All time'), selected: _range == 'all', onSelected: (_) => _setRange('all')),
                  ChoiceChip(label: const Text('365 days'), selected: _range == '365d', onSelected: (_) => _setRange('365d')),
                  ChoiceChip(label: const Text('90 days'), selected: _range == '90d', onSelected: (_) => _setRange('90d')),
                  ChoiceChip(label: const Text('30 days'), selected: _range == '30d', onSelected: (_) => _setRange('30d')),
                ],
              ),
              const SizedBox(height: 12),
              if (data != null) ...[
                _overallCard(data),
                const SizedBox(height: 12),
                _leaderboardCard(data),
                const SizedBox(height: 12),
                FutureBuilder<Insights>(
                  future: _insightsFuture,
                  builder: (context, insSnap) {
                    final ins = insSnap.data;
                    if (ins == null) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _insightsSummary(ins),
                        const SizedBox(height: 12),
                        _dowChartLite(ins),
                        const SizedBox(height: 12),
                        _hourChartLite(ins),
                      ],
                    );
                  },
                ),
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
                _metric('I initiated', '${d.mine} ($minePct%)'),
                const SizedBox(width: 16),
                _metric('They initiated', '${d.theirs} ($theirsPct%)'),
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
            const Text('Top contacts', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...d.leaderboard.map(_personRow),
          ],
        ),
      ),
    );
  }

  Widget _insightsSummary(Insights ins) {
    String fmt(double d) => d.isNaN || d.isInfinite ? '—' : d.toStringAsFixed(1);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            _metric('Avg gap', '${fmt(ins.avgGapDays)} days'),
            const SizedBox(width: 12),
            _metric('Longest streak', '${ins.longestStreakDays} days'),
            const SizedBox(width: 12),
            _metric('Longest gap', '${ins.longestGapDays} days'),
          ],
        ),
      ),
    );
  }

  Widget _dowChartLite(Insights ins) {
    final labels = const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final maxV = ins.dowCounts.isEmpty ? 1 : ins.dowCounts.reduce((a, b) => a > b ? a : b);
    final safeMax = maxV <= 0 ? 1 : maxV;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Interactions by day of week', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SizedBox(
              height: 180,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(7, (i) {
                  final v = ins.dowCounts[i];
                  final h = 140.0 * (v / safeMax);
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        width: 18,
                        height: h,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(labels[i], style: const TextStyle(fontSize: 12)),
                    ],
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hourChartLite(Insights ins) {
    final maxV = ins.hourCounts.isEmpty ? 1 : ins.hourCounts.reduce((a, b) => a > b ? a : b);
    final safeMax = maxV <= 0 ? 1 : maxV;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Interactions by hour', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SizedBox(
              height: 180,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(24, (i) {
                    final v = ins.hourCounts[i];
                    final h = 140.0 * (v / safeMax);
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            width: 10,
                            height: h,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (i % 3 == 0)
                            Text(i.toString().padLeft(2, '0'), style: const TextStyle(fontSize: 12))
                          else
                            const SizedBox(height: 14),
                        ],
                      ),
                    );
                  }),
                ),
              ),
            ),
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

class Insights {
  final double avgGapDays;
  final int longestStreakDays;
  final int longestGapDays;
  final List<int> dowCounts;
  final List<int> hourCounts;
  Insights({
    required this.avgGapDays,
    required this.longestStreakDays,
    required this.longestGapDays,
    required this.dowCounts,
    required this.hourCounts,
  });
}
