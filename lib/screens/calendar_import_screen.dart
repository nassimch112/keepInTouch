import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/material.dart';
import '../services/device_calendar_service.dart';
import '../services/calendar_import_service.dart';

class CalendarImportScreen extends StatefulWidget {
  const CalendarImportScreen({super.key});

  @override
  State<CalendarImportScreen> createState() => _CalendarImportScreenState();
}

class _CalendarImportScreenState extends State<CalendarImportScreen> {
  bool _loading = true;
  bool _permissionOk = false;
  List<Calendar> _calendars = const [];
  final Set<String> _selected = {};
  late DateTime _start;
  late DateTime _end;
  CalendarImportSummary? _summary;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _end = DateTime(now.year, now.month, now.day, 23, 59, 59);
    _start = _end.subtract(const Duration(days: 90));
    _init();
  }

  Future<void> _init() async {
    final ok = await DeviceCalendarService.ensurePermissions();
    List<Calendar> cals = const [];
    if (ok) {
      cals = await DeviceCalendarService.listCalendars();
    }
    setState(() {
      _permissionOk = ok;
      _calendars = cals;
      _selected.addAll(cals.where((c) => (c.isReadOnly ?? false) == false).map((c) => c.id!).whereType<String>());
      _loading = false;
    });
  }

  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 5)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: _start,
    );
    if (picked != null) setState(() => _start = picked);
  }

  Future<void> _pickEnd() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 5)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: _end,
    );
    if (picked != null) setState(() => _end = picked);
  }

  Future<void> _runImport() async {
    setState(() {
      _importing = true;
      _summary = null;
    });
    try {
      final summary = await CalendarImportService.importRange(
        start: _start,
        end: _end,
        calendarIds: _selected.isEmpty ? null : _selected.toList(),
      );
      if (!mounted) return;
      setState(() => _summary = summary);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported ${summary.imported}/${summary.scanned} • Skipped ${summary.skippedExisting} • Unmatched ${summary.unmatched}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _importing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import from phone calendar')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_permissionOk
              ? _PermissionDenied(onRetry: _init)
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _pickStart,
                              child: Text('Start: ${_fmtDate(_start)}'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _pickEnd,
                              child: Text('End: ${_fmtDate(_end)}'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView(
                        children: [
                          const ListTile(title: Text('Select calendars')),
                          ..._calendars.map((c) => CheckboxListTile(
                                value: _selected.contains(c.id),
                                onChanged: (v) {
                                  if (c.id == null) return;
                                  setState(() {
                                    if (v == true) {
                                      _selected.add(c.id!);
                                    } else {
                                      _selected.remove(c.id!);
                                    }
                                  });
                                },
                                title: Text(c.name ?? c.accountName ?? c.id ?? 'Calendar'),
                                subtitle: Text((c.isReadOnly ?? false) ? 'Read-only' : 'Writable'),
                              )),
                          if (_summary != null) ...[
                            const Divider(),
                            ListTile(
                              title: const Text('Last import summary'),
                              subtitle: Text('Scanned ${_summary!.scanned} • Imported ${_summary!.imported} • Skipped ${_summary!.skippedExisting} • Unmatched ${_summary!.unmatched}'),
                            )
                          ]
                        ],
                      ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: FilledButton.icon(
                          onPressed: _importing ? null : _runImport,
                          icon: _importing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.download),
                          label: const Text('Import now'),
                        ),
                      ),
                    )
                  ],
                ),
    );
  }

  String _fmtDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _PermissionDenied extends StatelessWidget {
  final VoidCallback onRetry;
  const _PermissionDenied({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Calendar permission denied'),
            const SizedBox(height: 8),
            FilledButton(onPressed: onRetry, child: const Text('Request again')),
          ],
        ),
      ),
    );
  }
}
