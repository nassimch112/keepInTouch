import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../services/db.dart';
import '../models.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import '../services/ui_state.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class HomeScreen extends StatefulWidget {
  final ValueListenable<int>? expandBatchSignal;
  const HomeScreen({super.key, this.expandBatchSignal});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<Database> _db;
  late PersonRepo _repo;
  List<Person> _due = [];
  List<Person> _upcoming = [];
  List<Person> _all = [];
  String _filter = 'All'; // All, Weekly, Bi-weekly, Monthly, Rarely
  String _relationFilter = 'All'; // All, Family, Relatives, Close Friends, Friends, Work
  bool _batchExpanded = false;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _db = AppDb.instance;
    _refresh();
    // Auto-expand batch on Sundays
    final now = DateTime.now();
    if (now.weekday == DateTime.sunday) {
      _batchExpanded = true;
    }
    // Listen for external requests to expand batch
    widget.expandBatchSignal?.addListener(_handleExpandSignal);
  }

  void _handleExpandSignal() {
    if (mounted) setState(() => _batchExpanded = true);
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expandBatchSignal != widget.expandBatchSignal) {
      oldWidget.expandBatchSignal?.removeListener(_handleExpandSignal);
      widget.expandBatchSignal?.addListener(_handleExpandSignal);
    }
  }

  @override
  void dispose() {
    widget.expandBatchSignal?.removeListener(_handleExpandSignal);
    super.dispose();
  }

  Future<void> _refresh() async {
    final db = await _db;
    _repo = PersonRepo(db);
    final due = await _repo.dueNow();
    final up = await _repo.upcoming();
    final all = await _repo.all();
    setState(() {
      _due = due;
      _upcoming = up;
      _all = all;
    });
  }

  // legacy dialog methods removed; using bottom sheet variants

  Future<void> _deletePerson(Person p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete person'),
        content: Text('Remove ${p.name}? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton.tonal(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true) {
      final db = await _db;
      final repo = PersonRepo(db);
      await repo.delete(p.id!);
      await _refresh();
    }
  }

  Future<void> _markDone(Person p) async {
    if (UiState.instance.haptics.value) HapticFeedback.lightImpact();
    final initiator = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).padding.bottom + 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: Text('Who initiated?')),
              ListTile(leading: const Icon(Icons.person_outline), title: const Text('I contacted'), onTap: () => Navigator.pop(ctx, 'me')),
              ListTile(leading: const Icon(Icons.group_outlined), title: const Text('They did'), onTap: () => Navigator.pop(ctx, 'them')),
            ],
          ),
        ),
      ),
    );
    if (initiator == null) return;
    await _repo.markDone(p.id!, initiator: initiator);
    await _refresh();
  }

  // snooze handled via bottom sheet picker

  bool _matchesFilter(Person p) {
    final timeOk = (() {
      switch (_filter) {
      case 'Weekly':
        return p.cadenceDays <= 7;
      case 'Bi-weekly':
        return p.cadenceDays > 7 && p.cadenceDays <= 14;
      case 'Monthly':
        return p.cadenceDays > 14 && p.cadenceDays <= 31;
      case 'Rarely':
        return p.cadenceDays > 31;
      default:
        return true;
      }
    })();
    final relOk = (() {
      if (_relationFilter == 'All') return true;
      if (_relationFilter == 'Favorites') return p.favorite;
      return p.tags.map((t) => t.toLowerCase()).contains(_relationFilter.toLowerCase());
    })();
    final query = _search.trim().toLowerCase();
    final searchOk = query.isEmpty
        ? true
        : (
            p.name.toLowerCase().contains(query) ||
            (p.phone ?? '').toLowerCase().contains(query) ||
            p.tags.any((t) => t.toLowerCase().contains(query))
          );
    return timeOk && relOk && searchOk;
  }

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(d.year, d.month, d.day);
    if (target == today) return 'Today';
    if (target == today.add(const Duration(days: 1))) return 'Tomorrow';
    return DateFormat('EEE, MMM d').format(d);
  }

  DateTime _nextDueFor(Person p) {
    final last = p.lastInteractionAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final next = last.add(Duration(days: p.cadenceDays));
    return next.isBefore(DateTime.now()) ? DateTime.now() : next;
  }

  Widget _personCard(Person p, {bool isDue = false, bool compact = false}) {
    final next = _nextDueFor(p);
  final borderSide = BorderSide(color: Colors.white.withValues(alpha: 0.08));
    final last = p.lastInteractionAt != null ? ' • Last: ${DateFormat('MMM d').format(p.lastInteractionAt!)}' : '';
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(radius: 14, child: Text(p.name.isNotEmpty ? p.name[0].toUpperCase() : '?')),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                p.name,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            Icon(p.favorite ? Icons.star : Icons.star_border, size: 18, color: p.favorite ? Colors.amber : Colors.white60),
            if (isDue)
              const Padding(
                padding: EdgeInsets.only(left: 8.0),
                child: Chip(label: Text('Due'), visualDensity: VisualDensity.compact, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Every ${p.cadenceDays} days', style: const TextStyle(color: Colors.white70)),
            const Text('•', style: TextStyle(color: Colors.white38)),
            Text('Next: ${_formatDate(next)}$last', style: const TextStyle(color: Colors.white70)),
            if (p.phone != null) ...[
              const Text('•', style: TextStyle(color: Colors.white38)),
              Text(p.phone!, style: const TextStyle(color: Colors.white60)),
            ],
          ],
        ),
        if (p.tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: p.tags.map((t) => _tagChip(t)).toList(),
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (p.phone != null) ...[
              IconButton(icon: const Icon(Icons.sms), tooltip: 'SMS', onPressed: () => launchUrl(Uri.parse('sms:${p.phone}'))),
              IconButton(icon: const Icon(Icons.call), tooltip: 'Call', onPressed: () => launchUrl(Uri.parse('tel:${p.phone}'))),
            ],
            IconButton(icon: const Icon(Icons.snooze), tooltip: 'Snooze', onPressed: () => _showSnoozePicker(p)),
            const Spacer(),
            IconButton(icon: const Icon(Icons.edit), tooltip: 'Edit', onPressed: () { if (UiState.instance.haptics.value) HapticFeedback.selectionClick(); _openEditPersonSheet(p); }),
            IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Delete', onPressed: () { if (UiState.instance.haptics.value) HapticFeedback.heavyImpact(); _deletePerson(p); }),
            _animatedDoneButton(p),
          ],
        ),
      ],
    );
    final card = InkWell(
      borderRadius: BorderRadius.circular(16),
      onLongPress: () => _openEditPersonSheet(p),
      child: Card(
        elevation: compact ? 1.5 : 3,
  shadowColor: Colors.black.withValues(alpha: 0.35),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: borderSide),
        margin: EdgeInsets.symmetric(horizontal: 12, vertical: compact ? 4 : 10),
        child: Padding(padding: EdgeInsets.all(compact ? 10 : 14), child: content),
      ),
    );
    if (compact) return card; // Do not enable swipe in compact/batch tiles
    return Dismissible(
      key: ValueKey('p_${p.id}'),
      background: Container(
        margin: EdgeInsets.symmetric(horizontal: 12, vertical: compact ? 4 : 10),
        decoration: BoxDecoration(color: Colors.green.shade700, borderRadius: BorderRadius.circular(16)),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Row(children: [Icon(Icons.check, color: Colors.white), SizedBox(width: 8), Text('Done', style: TextStyle(color: Colors.white))]),
      ),
      secondaryBackground: Container(
        margin: EdgeInsets.symmetric(horizontal: 12, vertical: compact ? 4 : 10),
        decoration: BoxDecoration(color: Colors.orange.shade800, borderRadius: BorderRadius.circular(16)),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Row(mainAxisAlignment: MainAxisAlignment.end, children: [Icon(Icons.snooze, color: Colors.white), SizedBox(width: 8), Text('Snooze 7d', style: TextStyle(color: Colors.white))]),
      ),
      onDismissed: (direction) async {
        final prevLast = p.lastInteractionAt;
        final prevSnooze = p.snoozeUntil;
        if (direction == DismissDirection.startToEnd) {
          await _repo.markDone(p.id!, initiator: 'me');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Marked ${p.name} done'),
                action: SnackBarAction(
                  label: 'Undo',
                  onPressed: () async {
                    await _repo.update(Person(
                      id: p.id,
                      name: p.name,
                      phone: p.phone,
                      cadenceDays: p.cadenceDays,
                      notes: p.notes,
                      tags: p.tags,
                      preferredWindow: p.preferredWindow,
                      specialDates: p.specialDates,
                      lastInteractionAt: prevLast,
                      snoozeUntil: prevSnooze,
                      favorite: p.favorite,
                    ));
                    await _refresh();
                  },
                ),
              ),
            );
          }
        } else {
          await _repo.snooze(p.id!, const Duration(days: 7));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Snoozed ${p.name} 7 days'),
                action: SnackBarAction(
                  label: 'Undo',
                  onPressed: () async {
                    await _repo.update(Person(
                      id: p.id,
                      name: p.name,
                      phone: p.phone,
                      cadenceDays: p.cadenceDays,
                      notes: p.notes,
                      tags: p.tags,
                      preferredWindow: p.preferredWindow,
                      specialDates: p.specialDates,
                      lastInteractionAt: prevLast,
                      snoozeUntil: prevSnooze,
                      favorite: p.favorite,
                    ));
                    await _refresh();
                  },
                ),
              ),
            );
          }
        }
        await _refresh();
      },
      child: card,
    );
  }

  Future<void> _showSnoozePicker(Person p) async {
    final picked = await showModalBottomSheet<Duration>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).padding.bottom + 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(title: Text('Snooze')),
                ListTile(title: const Text('30 minutes'), onTap: () => Navigator.pop(ctx, const Duration(minutes: 30))),
                ListTile(title: const Text('1 hour'), onTap: () => Navigator.pop(ctx, const Duration(hours: 1))),
                ListTile(title: const Text('3 hours'), onTap: () => Navigator.pop(ctx, const Duration(hours: 3))),
                ListTile(title: const Text('Tomorrow'), onTap: () => Navigator.pop(ctx, const Duration(days: 1))),
                ListTile(
                  title: const Text('Next Sunday'),
                  onTap: () {
                    final now = DateTime.now();
                    final daysUntil = (DateTime.sunday - now.weekday + 7) % 7;
                    final days = daysUntil == 0 ? 7 : daysUntil;
                    Navigator.pop(ctx, Duration(days: days));
                  },
                ),
                ListTile(title: const Text('Next week'), onTap: () => Navigator.pop(ctx, const Duration(days: 7))),
              ],
            ),
          ),
        );
      },
    );
    if (picked != null) {
      await _repo.snooze(p.id!, picked);
      await _refresh();
    }
  }

  Widget _tagChip(String label) {
    final color = _tagColor(label);
    return Chip(
      label: Text(label),
      backgroundColor: color.withValues(alpha: 0.15),
      side: BorderSide(color: color.withValues(alpha: 0.35)),
      labelStyle: TextStyle(color: color),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Color _tagColor(String label) {
    switch (label.toLowerCase()) {
      case 'family':
        return Colors.pinkAccent;
      case 'relatives':
        return Colors.orangeAccent;
      case 'close friends':
      case 'close':
        return Colors.lightBlueAccent;
      case 'friends':
        return Colors.greenAccent;
      case 'work':
        return Colors.amberAccent;
      default:
        return Colors.purpleAccent;
    }
  }

  Widget _animatedDoneButton(Person p) => _DoneIconButton(onDone: () => _markDone(p));

  // Removed recently-done tiles; main list resorts after Done

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 140,
              backgroundColor: Colors.transparent,
              flexibleSpace: LayoutBuilder(
                builder: (context, constraints) {
                  final t = ((constraints.maxHeight - kToolbarHeight) / (140 - kToolbarHeight)).clamp(0.0, 1.0);
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      // Animated gradient background
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 600),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Color.lerp(const Color(0xFF06b6d4), const Color(0xFF0ea5e9), t)!,
                              Color.lerp(const Color(0xFF0ea5e9), const Color(0xFF6366f1), t)!,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                      ),
                      // Title + Search embedded in banner
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 10,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Keep in touch', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            TextField(
                              decoration: InputDecoration(
                                fillColor: Colors.black.withValues(alpha: 0.15),
                                filled: true,
                                prefixIcon: const Icon(Icons.search),
                                hintText: 'Search name, phone, tag',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                                isDense: true,
                                suffixIcon: _search.isEmpty
                                    ? null
                                    : IconButton(
                                        icon: const Icon(Icons.clear),
                                        onPressed: () => setState(() => _search = ''),
                                      ),
                              ),
                              onChanged: (v) => setState(() => _search = v),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
              pinned: false,
              floating: false,
            ),
            // Global cadence filters under header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSummaryChip(),
                    const SizedBox(height: 8),
                    _buildFilterChips(),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
                child: _buildBatchSection(),
              ),
            ),
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text('All contacts', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  final filtered = _all
                      .where(_matchesFilter)
                      .toList()
                    ..sort((a, b) => _nextDueFor(a).compareTo(_nextDueFor(b)));
                  if (i >= filtered.length) return null;
                  final p = filtered[i];
                  final isDue = _due.any((d) => d.id == p.id);
                  return _personCard(p, isDue: isDue);
                },
              ),
            ),
            // No duplicate 'recently done' entries; list is re-sorted
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: _openAddPersonSheet,
        icon: const Icon(Icons.person_add),
        label: const Text('Add'),
      ),
    );
  }

  Widget _buildBatchSection() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: ExpansionTile(
        initiallyExpanded: _batchExpanded,
        onExpansionChanged: (v) => setState(() => _batchExpanded = v),
        leading: const Icon(Icons.bolt),
        title: const Text('Batch mode'),
        subtitle: Text(_due.where(_matchesFilter).isEmpty ? 'Nothing due now' : '${_due.where(_matchesFilter).length} due'),
        children: [
          // Note: Filters moved to top of Home screen
          if (_due.where(_matchesFilter).isEmpty)
            const Padding(
              padding: EdgeInsets.all(12.0),
              child: Text('All caught up!'),
            )
          else
            Wrap(
              children: [
                ..._due
                    .where(_matchesFilter)
                    .map((p) => _personCard(p, isDue: true, compact: true)),
              ],
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
  final timeFilters = const ['All', 'Weekly', 'Bi-weekly', 'Monthly', 'Rarely'];
  final relationFilters = const ['All', 'Favorites', 'Family', 'Relatives', 'Close Friends', 'Friends', 'Work'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            itemBuilder: (ctx, i) {
              final f = timeFilters[i];
              return ChoiceChip(
                label: Text(f),
                selected: _filter == f,
                onSelected: (_) => setState(() => _filter = f),
              );
            },
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemCount: timeFilters.length,
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            itemBuilder: (ctx, i) {
              final f = relationFilters[i];
              return ChoiceChip(
                label: Text(f),
                selected: _relationFilter == f,
                onSelected: (_) => setState(() => _relationFilter = f),
              );
            },
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemCount: relationFilters.length,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryChip() {
    final dueCount = _due.where(_matchesFilter).length;
    final upcomingCount = _upcoming.where(_matchesFilter).length;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.today, size: 18),
          const SizedBox(width: 6),
          Text('$dueCount due • $upcomingCount upcoming'),
        ],
      ),
    );
  }

  // Removed unused _matchesFilterCadence; using _matchesFilter(Person)

  Future<void> _openAddPersonSheet() async {
    final result = await showModalBottomSheet<_PersonFormResult>(
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
            child: const _PersonForm(initialCadence: 14, initialTags: [], initialFavorite: false),
          ),
        ),
      ),
    );
    if (result != null) {
      final db = await _db;
      final repo = PersonRepo(db);
      await repo.add(Person(
        name: result.name,
        phone: result.phone,
        cadenceDays: result.cadenceDays,
        notes: result.notes,
        tags: result.tags,
        favorite: result.favorite,
      ));
      await _refresh();
    }
  }

  Future<void> _openEditPersonSheet(Person p) async {
    final result = await showModalBottomSheet<_PersonFormResult>(
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
            child: _PersonForm(
              initialName: p.name,
              initialPhone: p.phone,
              initialNotes: p.notes,
              initialCadence: p.cadenceDays,
              initialTags: p.tags,
              initialFavorite: p.favorite,
            ),
          ),
        ),
      ),
    );
    if (result != null) {
      final db = await _db;
      final repo = PersonRepo(db);
      await repo.update(Person(
        id: p.id,
        name: result.name,
        phone: result.phone,
        cadenceDays: result.cadenceDays,
        tags: result.tags,
        preferredWindow: p.preferredWindow,
        notes: result.notes,
        specialDates: p.specialDates,
        lastInteractionAt: p.lastInteractionAt,
        snoozeUntil: p.snoozeUntil,
        favorite: result.favorite,
      ));
      await _refresh();
    }
  }

}

class _DoneIconButton extends StatefulWidget {
  final Future<void> Function() onDone;
  const _DoneIconButton({required this.onDone});
  @override
  State<_DoneIconButton> createState() => _DoneIconButtonState();
}

class _DoneIconButtonState extends State<_DoneIconButton> {
  bool _anim = false;
  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: AnimatedScale(
        scale: _anim ? 1.2 : 1.0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        child: Icon(_anim ? Icons.check_circle : Icons.check_circle_outline, color: _anim ? Colors.greenAccent : null),
      ),
      tooltip: 'Done',
      onPressed: () async {
        setState(() => _anim = true);
        await Future.delayed(const Duration(milliseconds: 160));
        await widget.onDone();
        await Future.delayed(const Duration(milliseconds: 100));
        if (mounted) setState(() => _anim = false);
      },
    );
  }
}

// Removed legacy _DoneEntry and recently-done UI; list reorders after Done

class _PersonFormResult {
  final String name;
  final String? phone;
  final String? notes;
  final int cadenceDays;
  final List<String> tags;
  final bool favorite;
  _PersonFormResult({required this.name, this.phone, this.notes, required this.cadenceDays, this.tags = const [], this.favorite = false});
}

class _PersonForm extends StatefulWidget {
  final String? initialName;
  final String? initialPhone;
  final String? initialNotes;
  final int initialCadence; // in days
  final List<String> initialTags;
  final bool initialFavorite;
  const _PersonForm({this.initialName, this.initialPhone, this.initialNotes, required this.initialCadence, this.initialTags = const [], this.initialFavorite = false});
  @override
  State<_PersonForm> createState() => _PersonFormState();
}

class _PersonFormState extends State<_PersonForm> {
  late TextEditingController _name;
  late TextEditingController _phone;
  late TextEditingController _notes;
  late int _cadenceDays;
  late bool _favorite;
  final List<String> _allTags = const ['Family', 'Relatives', 'Close Friends', 'Friends', 'Work'];
  late Set<String> _tags;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName ?? '');
    _phone = TextEditingController(text: widget.initialPhone ?? '');
    _notes = TextEditingController(text: widget.initialNotes ?? '');
    _cadenceDays = widget.initialCadence;
    _favorite = widget.initialFavorite;
    _tags = {...widget.initialTags};
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _notes.dispose();
    super.dispose();
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

  String _labelForCadence(int days) {
    if (days <= 7) return 'Weekly';
    if (days <= 14) return 'Bi-weekly';
    if (days <= 31) return 'Monthly';
    return 'Rarely';
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
              const Expanded(child: Text('Person', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
              IconButton(
                icon: Icon(_favorite ? Icons.star : Icons.star_border, color: _favorite ? Colors.amber : Colors.white70),
                tooltip: _favorite ? 'Unfavorite' : 'Favorite',
                onPressed: () => setState(() => _favorite = !_favorite),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Name',
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone (optional)',
              prefixIcon: Icon(Icons.call_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              prefixIcon: Icon(Icons.note_outlined),
              border: OutlineInputBorder(),
            ),
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
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
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
                      _PersonFormResult(
                        name: name,
                        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
                        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
                        cadenceDays: _cadenceDays,
                        tags: _tags.toList(),
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

