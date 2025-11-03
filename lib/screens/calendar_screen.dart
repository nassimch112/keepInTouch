import 'package:flutter/material.dart';
import '../services/db.dart';
import '../models.dart';
// import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import '../services/ui_state.dart';
import '../services/device_calendar_service.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/settings.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  int? _selectedDay;
  late Future<PersonRepo> _repo;
  List<Person> _people = [];
  bool _deviceCalEnabled = false;
  Map<int, int> _deviceEventCounts = {};
  Map<int, List<String>> _deviceEventTitles = {};
  // Cache per month key 'yyyy-mm'
  final Map<String, Map<int, int>> _countsCache = {};
  final Map<String, Map<int, List<String>>> _titlesCache = {};
  // Cache people-by-day per month to avoid recompute in every build
  final Map<String, Map<int, List<Person>>> _peopleCache = {};

  @override
  void initState() {
    super.initState();
    _repo = AppDb.instance.then((db) => PersonRepo(db));
    _load();
  }

  Future<void> _load() async {
    final repo = await _repo;
    _people = await repo.all();
    // Invalidate people map cache when people list changes
    _peopleCache.clear();
    _deviceCalEnabled = await SettingsService.getDeviceCalendarEnabled();
    if (_deviceCalEnabled) {
      await _loadDeviceCalendar();
      _prefetchAdjacent();
    }
    if (mounted) setState(() {});
  }

  String _keyFor(DateTime m) => '${m.year}-${m.month.toString().padLeft(2, '0')}';

  Future<void> _loadDeviceCalendar({DateTime? month}) async {
    final ok = await DeviceCalendarService.ensurePermissions();
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Calendar permission denied'),
            action: SnackBarAction(label: 'Open settings', onPressed: openAppSettings),
          ),
        );
      }
      return;
    }
    final m = DateTime((month ?? _month).year, (month ?? _month).month, 1);
    final key = _keyFor(m);
    if (_countsCache.containsKey(key)) {
      if (m.year == _month.year && m.month == _month.month) {
        _deviceEventCounts = _countsCache[key]!;
        _deviceEventTitles = _titlesCache[key]!;
        if (mounted) setState(() {});
      }
    }
    final start = DateTime(m.year, m.month, 1);
    final end = DateTime(m.year, m.month + 1, 0, 23, 59, 59);
    final events = await DeviceCalendarService.fetchEvents(start: start, end: end);
    final counts = <int, int>{};
    final titles = <int, List<String>>{};
    for (final e in events) {
      final d = e.start?.day;
      if (d == null) continue;
      counts[d] = (counts[d] ?? 0) + 1;
      titles.putIfAbsent(d, () => <String>[]).add(e.title ?? 'Event');
    }
    _countsCache[key] = counts;
    _titlesCache[key] = titles;
    if (m.year == _month.year && m.month == _month.month) {
      _deviceEventCounts = counts;
      _deviceEventTitles = titles;
      if (mounted) setState(() {});
    }
  }

  void _prefetchAdjacent() {
    final prev = DateTime(_month.year, _month.month - 1, 1);
    final next = DateTime(_month.year, _month.month + 1, 1);
    _loadDeviceCalendar(month: prev);
    _loadDeviceCalendar(month: next);
  }

  DateTime _nextDue(Person p) {
    final last = p.lastInteractionAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return last.add(Duration(days: p.cadenceDays));
  }

  Map<int, List<Person>> _peopleByDay(DateTime month) {
    final key = _keyFor(DateTime(month.year, month.month, 1));
    final cached = _peopleCache[key];
    if (cached != null) return cached;
    final first = DateTime(month.year, month.month, 1);
    final last = DateTime(month.year, month.month + 1, 0);
    final map = <int, List<Person>>{};
    for (final p in _people) {
      final d = _nextDue(p);
      if (!d.isBefore(first) && !d.isAfter(last)) {
        map.putIfAbsent(d.day, () => []).add(p);
      }
    }
    _peopleCache[key] = map;
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final map = _peopleByDay(_month);
    final firstWeekday = DateTime(_month.year, _month.month, 1).weekday % 7; // 0=Sun
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final cells = <Widget>[];
    for (var i = 0; i < firstWeekday; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var d = 1; d <= daysInMonth; d++) {
      final people = map[d] ?? const [];
      final dotCount = people.length > 5 ? 5 : people.length;
      final selected = _selectedDay == d;
      cells.add(GestureDetector(
        onTap: () => setState(() => _selectedDay = d),
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: selected ? Colors.blueAccent : Colors.white12),
            color: selected ? const Color(0xFF0b1224) : null,
          ),
          padding: const EdgeInsets.all(4),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Day number top-left
              Align(
                alignment: Alignment.topLeft,
                child: Text('$d', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
              ),
              // People dots centered
              if (dotCount > 0)
                Center(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 2,
                    runSpacing: 2,
                    children: List.generate(
                      dotCount,
                      (i) => const Icon(Icons.circle, size: 6, color: Colors.white70),
                    ),
                  ),
                ),
              // Device events badge bottom-right
              if (_deviceCalEnabled && (_deviceEventCounts[d] ?? 0) > 0)
                Align(
                  alignment: Alignment.bottomRight,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.event, size: 10, color: Colors.white60),
                        const SizedBox(width: 2),
                        Text('${_deviceEventCounts[d]}', style: const TextStyle(fontSize: 10, color: Colors.white60)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ));
    }
    return Column(
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Row(
              children: [
                IconButton(
                  iconSize: 28,
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  tooltip: 'Previous month',
                  onPressed: () async {
                    if (UiState.instance.haptics.value) HapticFeedback.selectionClick();
                    setState(() => _month = DateTime(_month.year, _month.month - 1, 1));
                    if (_deviceCalEnabled) {
                      await _loadDeviceCalendar();
                      _prefetchAdjacent();
                      if (mounted) setState(() {});
                    }
                  },
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      transitionBuilder: (child, anim) => SlideTransition(
                        position: Tween<Offset>(begin: const Offset(0.1, 0), end: Offset.zero).animate(anim),
                        child: FadeTransition(opacity: anim, child: child),
                      ),
                      child: Text(
                        '${_month.year}-${_month.month.toString().padLeft(2, '0')}',
                        key: ValueKey('${_month.year}-${_month.month}'),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  iconSize: 28,
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  tooltip: 'Next month',
                  onPressed: () async {
                    if (UiState.instance.haptics.value) HapticFeedback.selectionClick();
                    setState(() => _month = DateTime(_month.year, _month.month + 1, 1));
                    if (_deviceCalEnabled) {
                      await _loadDeviceCalendar();
                      _prefetchAdjacent();
                      if (mounted) setState(() {});
                    }
                  },
                  icon: const Icon(Icons.chevron_right),
                ),
                TextButton(
                  onPressed: () async {
                    if (UiState.instance.haptics.value) HapticFeedback.selectionClick();
                    setState(() {
                      final now = DateTime.now();
                      _selectedDay = now.day;
                      _month = DateTime(now.year, now.month, 1);
                    });
                    if (_deviceCalEnabled) {
                      await _loadDeviceCalendar();
                      _prefetchAdjacent();
                      if (mounted) setState(() {});
                    }
                  },
                  child: const Text('Today'),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Column(
            children: [
              // Weekday headers
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: const [
                    Expanded(child: Center(child: Text('S'))),
                    Expanded(child: Center(child: Text('M'))),
                    Expanded(child: Center(child: Text('T'))),
                    Expanded(child: Center(child: Text('W'))),
                    Expanded(child: Center(child: Text('T'))),
                    Expanded(child: Center(child: Text('F'))),
                    Expanded(child: Center(child: Text('S'))),
                  ],
                ),
              ),
              Expanded(
                flex: 3,
                child: GridView.count(
                  crossAxisCount: 7,
                  childAspectRatio: 0.9,
                  children: cells,
                ),
              ),
              const Divider(height: 1),
              // Details panel for selected day
              Expanded(
                flex: 2,
                child: _buildDayDetails(map),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDayDetails(Map<int, List<Person>> map) {
    final day = _selectedDay;
    if (day == null) {
      return const Center(child: Text('Tap a day to see details'));
    }
    final people = map[day] ?? const [];
    final deviceTitles = _deviceEventTitles[day] ?? const [];
    if (people.isEmpty && deviceTitles.isEmpty) {
      return const Center(child: Text('No items this day'));
    }
    final items = <Widget>[];
    if (_deviceCalEnabled && deviceTitles.isNotEmpty) {
      items.add(Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Row(children: const [Icon(Icons.event, size: 16), SizedBox(width: 6), Text('Device events')]),
      ));
      items.addAll(deviceTitles.take(5).map((t) => ListTile(title: Text(t), leading: const Icon(Icons.event_note))));
      if (deviceTitles.length > 5) {
        items.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('+${deviceTitles.length - 5} more', style: const TextStyle(color: Colors.white60)),
        ));
      }
      items.add(const Divider());
    }
    items.addAll(List.generate(people.length, (i) => _personDetailCard(people[i])));
    return ListView(children: items);
  }

  Widget _personDetailCard(Person p) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        leading: _avatar(p.name),
        title: Row(
          children: [
            Expanded(
              child: Text(
                p.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (p.favorite) const Icon(Icons.star, size: 18, color: Colors.amber),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Every ${p.cadenceDays} days${p.tags.isNotEmpty ? ' · ${p.tags.take(3).join(', ')}' : ''}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        onTap: () async {
          // Open edit sheet on tap
          final updated = await showModalBottomSheet<Person>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (ctx) => SafeArea(
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _EditPersonSheet(person: p),
                ),
              ),
            ),
          );
          if (updated != null) {
            final repo = await _repo;
            await repo.update(updated);
            await _load();
          }
        },
        onLongPress: () async {
          // Quick actions on long press
          final action = await showModalBottomSheet<String>(
            context: context,
            showDragHandle: true,
            builder: (ctx) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ListTile(title: Text('Actions')),
                  ListTile(title: const Text('Snooze 1 week'), onTap: () => Navigator.pop(ctx, 'snooze_7d')),
                  ListTile(title: const Text('Mark Done'), onTap: () => Navigator.pop(ctx, 'done')),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
          if (action == 'snooze_7d') {
            final repo = await _repo;
            await repo.snooze(p.id!, const Duration(days: 7));
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Snoozed')));
            await _load();
          } else if (action == 'done') {
            if (UiState.instance.haptics.value) HapticFeedback.lightImpact();
            final repo = await _repo;
            await repo.markDone(p.id!, initiator: 'me');
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marked done')));
            await _load();
          }
        },
      ),
    );
  }

  Widget _avatar(String name) {
    final c1 = _colorFromName(name, 0.55);
    final c2 = _colorFromName(name, 0.85);
    return ClipOval(
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [c1, c2], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        alignment: Alignment.center,
        child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  Color _colorFromName(String name, double sat) {
    final hash = name.runes.fold<int>(0, (p, c) => (p * 31 + c) & 0x7fffffff);
    final hue = (hash % 360).toDouble();
    return HSVColor.fromAHSV(1, hue, sat, 0.55).toColor();
  }
}

class _EditPersonSheet extends StatefulWidget {
  final Person person;
  const _EditPersonSheet({required this.person});
  @override
  State<_EditPersonSheet> createState() => _EditPersonSheetState();
}

class _EditPersonSheetState extends State<_EditPersonSheet> {
  late TextEditingController _name;
  late TextEditingController _phone;
  late int _cadenceDays;
  late bool _favorite;
  late Set<String> _tags;
  final List<String> _allTags = const ['Family', 'Relatives', 'Close Friends', 'Friends', 'Work'];

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.person.name);
    _phone = TextEditingController(text: widget.person.phone ?? '');
    _cadenceDays = widget.person.cadenceDays;
    _favorite = widget.person.favorite;
    _tags = {...widget.person.tags};
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  String _labelForCadence(int days) {
    if (days <= 7) return 'Weekly';
    if (days <= 14) return 'Bi-weekly';
    if (days <= 31) return 'Monthly';
    return 'Rarely';
  }

  void _setCadence(String label) {
    switch (label) {
      case 'Weekly':
        _cadenceDays = 7;
        break;
      case 'Bi-weekly':
        _cadenceDays = 14;
        break;
      case 'Monthly':
        _cadenceDays = 30;
        break;
      case 'Rarely':
        _cadenceDays = 60;
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filters = ['Weekly', 'Bi-weekly', 'Monthly', 'Rarely'];
    final selected = _labelForCadence(_cadenceDays);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Text('Edit person', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
              IconButton(
                icon: Icon(_favorite ? Icons.star : Icons.star_border, color: _favorite ? Colors.amber : Colors.white70),
                onPressed: () => setState(() => _favorite = !_favorite),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          const Text('Tags'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: _allTags
                .map((t) => FilterChip(
                      label: Text(t),
                      selected: _tags.contains(t),
                      onSelected: (sel) => setState(() {
                        if (sel) {
                          _tags.add(t);
                        } else {
                          _tags.remove(t);
                        }
                      }),
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),
          const Text('Cadence'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: filters
                .map((f) => ChoiceChip(
                      label: Text(f),
                      selected: selected == f,
                      onSelected: (_) => setState(() => _setCadence(f)),
                    ))
                .toList(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    final name = _name.text.trim();
                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name is required')));
                      return;
                    }
                    Navigator.pop(
                      context,
                      Person(
                        id: widget.person.id,
                        name: name,
                        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
                        cadenceDays: _cadenceDays,
                        notes: widget.person.notes,
                        tags: _tags.toList(),
                        preferredWindow: widget.person.preferredWindow,
                        specialDates: widget.person.specialDates,
                        lastInteractionAt: widget.person.lastInteractionAt,
                        snoozeUntil: widget.person.snoozeUntil,
                        favorite: _favorite,
                      ),
                    );
                  },
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}