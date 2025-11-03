import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/device_calendar_service.dart';
import '../services/settings.dart';
import '../services/background.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';
import '../services/db.dart';
import '../services/ui_state.dart';
import 'calendar_import_screen.dart';
// Device calendar integration is automatic from Calendar tab; no manual import here
import 'package:url_launcher/url_launcher.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  TimeOfDay _daily = const TimeOfDay(hour: 19, minute: 30);
  bool _perPerson = true;
  Color _bg = const Color(0xFF0f172a);
  Color _card = const Color(0xFF111827);
  bool _haptics = true;
  bool _deviceCalendar = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final t = await SettingsService.getDailyReminderTime();
    final pp = await SettingsService.getPerPersonNudges();
    final theme = await SettingsService.getThemeColors();
    final h = await SettingsService.getHapticsEnabled();
    final dc = await SettingsService.getDeviceCalendarEnabled();
    setState(() {
      _daily = t;
      _perPerson = pp;
      _bg = theme.$1;
      _card = theme.$2;
      _haptics = h;
      _deviceCalendar = dc;
    });
  }

  // no-op legacy reader removed

  Future<void> _save() async {
    await SettingsService.setDailyReminderTime(_daily);
    await SettingsService.setPerPersonNudges(_perPerson);
    await UiState.instance.setHaptics(_haptics);
    await UiState.instance.setTheme(background: _bg, card: _card);
    await SettingsService.setDeviceCalendarEnabled(_deviceCalendar);
    await BackgroundScheduler.scheduleDailyAt(_daily);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
  }

  Future<void> _pickDailyTime() async {
    final initial = _daily;
    final t = await showTimePicker(context: context, initialTime: initial);
    if (t != null) {
      setState(() => _daily = t);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const ListTile(title: Text('Daily reminder time')),
        ListTile(
          title: Text(_daily.format(context)),
          trailing: const Icon(Icons.schedule),
          onTap: _pickDailyTime,
        ),
        SwitchListTile(
          title: const Text('Per-person nudges'),
          subtitle: const Text('Also send individual notifications for Due contacts'),
          value: _perPerson,
          onChanged: (v) => setState(() => _perPerson = v),
        ),
        // Removed compact list density setting per latest design direction
        SwitchListTile(
          title: const Text('Haptics (vibration)'),
          subtitle: const Text('Tap feedback for actions like Done/Snooze'),
          value: _haptics,
          onChanged: (v) => setState(() => _haptics = v),
        ),
        SwitchListTile(
          title: const Text('Show device calendar'),
          subtitle: const Text('Read-only overlay of device events/holidays'),
          value: _deviceCalendar,
          onChanged: (v) async {
            if (v) {
              final ok = await DeviceCalendarService.ensurePermissions();
              if (ok) {
                setState(() => _deviceCalendar = true);
              } else {
                if (!mounted) return;
                setState(() => _deviceCalendar = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Calendar permission denied'),
                    action: SnackBarAction(label: 'Open settings', onPressed: openAppSettings),
                  ),
                );
              }
            } else {
              setState(() => _deviceCalendar = false);
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.download),
          title: const Text('Import from phone calendar'),
          subtitle: const Text('Create interactions from past events'),
          onTap: () {
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CalendarImportScreen()));
          },
        ),
        const ListTile(title: Text('Theme')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            children: [
              _presetButton('Deep Sea', const Color(0xFF0f172a), const Color(0xFF111827)),
              _presetButton('Forest', const Color(0xFF0f1f14), const Color(0xFF11221a)),
              _presetButton('Sunset', const Color(0xFF1a0f12), const Color(0xFF221116)),
              _presetButton('Mono', const Color(0xFF121212), const Color(0xFF1E1E1E)),
            ],
          ),
        ),
        ListTile(
          title: const Text('Background'),
          trailing: CircleAvatar(backgroundColor: _bg),
          onTap: () async {
            final c = await showDialog<Color?>(
              context: context,
              builder: (ctx) => _ColorPickerDialog(initial: _bg),
            );
            if (c != null) setState(() => _bg = c);
          },
        ),
        ListTile(
          title: const Text('Card'),
          trailing: CircleAvatar(backgroundColor: _card),
          onTap: () async {
            final c = await showDialog<Color?>(
              context: context,
              builder: (ctx) => _ColorPickerDialog(initial: _card),
            );
            if (c != null) setState(() => _card = c);
          },
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.file_download),
          title: const Text('Export data to JSON'),
          subtitle: const Text('Saves people, interactions, and special dates'),
          onTap: _exportData,
        ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About'),
            onTap: _showAbout,
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('Save')),
        ),
        const SizedBox(height: 80),
      ],
    );
  }

  Future<void> _exportData() async {
    final db = await AppDb.instance;
    final people = await db.query('person');
    final interactions = await db.query('interaction');
    final special = await db.query('special_date');
    final payload = {
      'exportedAt': DateTime.now().toIso8601String(),
      'people': people,
      'interactions': interactions,
      'special_dates': special,
    };
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/keepintouch_export_${DateTime.now().millisecondsSinceEpoch}.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Exported to ${file.path}')));
  }

  Widget _presetButton(String label, Color bg, Color card) {
    final isSel = _bg.value == bg.value && _card.value == card.value;
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        backgroundColor: isSel ? bg.withOpacity(0.25) : null,
      ),
      onPressed: () => setState(() {
        _bg = bg;
        _card = card;
      }),
      child: Text(label),
    );
  }

  Future<void> _showAbout() async {
    if (!mounted) return;
    final repoUrl = const String.fromEnvironment('APP_REPO_URL', defaultValue: 'https://github.com/nassimch112/keepInTouch');
    final version = const String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0+1');
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
              const Text('KeepInTouch', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Version $version'),
              const SizedBox(height: 12),
              const Text('Local‑first, privacy‑respecting reminders to keep relationships warm.'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.book_outlined),
                    label: const Text('README'),
                    onPressed: () => launchUrl(Uri.parse('$repoUrl#readme')),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.privacy_tip_outlined),
                    label: const Text('Privacy'),
                    onPressed: () => launchUrl(Uri.parse('$repoUrl#privacy')),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text('Built by Nassim, with GitHub Copilot assisting on implementation and polish.'),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorPickerDialog extends StatefulWidget {
  final Color initial;
  const _ColorPickerDialog({required this.initial});
  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late double _hue;
  late double _sat;
  late double _val;

  @override
  void initState() {
    super.initState();
    final hsv = HSVColor.fromColor(widget.initial);
    _hue = hsv.hue;
    _sat = hsv.saturation;
    _val = hsv.value;
  }

  @override
  Widget build(BuildContext context) {
    final color = HSVColor.fromAHSV(1, _hue, _sat, _val).toColor();
    return AlertDialog(
      title: const Text('Pick a color'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(radius: 20, backgroundColor: color),
          const SizedBox(height: 12),
          _slider('Hue', _hue, 0, 360, (v) => setState(() => _hue = v)),
          _slider('Saturation', _sat, 0, 1, (v) => setState(() => _sat = v)),
          _slider('Value', _val, 0, 1, (v) => setState(() => _val = v)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, color), child: const Text('Select')),
      ],
    );
  }

  Widget _slider(String label, double value, double min, double max, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 90, child: Text(label)),
        Expanded(
          child: Slider(
            min: min,
            max: max,
            value: value,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
