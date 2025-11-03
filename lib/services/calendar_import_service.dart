import 'dart:async';
import 'package:device_calendar/device_calendar.dart';
import 'package:sqflite/sqflite.dart' as sql;
import 'package:flutter/foundation.dart';
// ignore_for_file: unused_import
import 'db.dart';
import 'device_calendar_service.dart';

/// Contract
/// - Inputs: date range [start, end], optional selected calendar IDs
/// - Behavior: fetch device events, map to people by name fuzzy match, create interactions
/// - Deduplication: use interaction.externalId = `device:{calendarId}:{eventId}` unique index
/// - Outputs: summary with counts
class CalendarImportSummary {
  final int scanned;
  final int imported;
  final int skippedExisting;
  final int unmatched;
  CalendarImportSummary({required this.scanned, required this.imported, required this.skippedExisting, required this.unmatched});
}

class CalendarImportService {
  static Future<CalendarImportSummary> importRange({
    required DateTime start,
    required DateTime end,
    List<String>? calendarIds,
  }) async {
    // Ensure permissions
    final ok = await DeviceCalendarService.ensurePermissions();
    if (!ok) throw StateError('Calendar permission denied');

    // Fetch events
    final events = <Event>[];
    if (calendarIds != null && calendarIds.isNotEmpty) {
      for (final id in calendarIds) {
        final ev = await DeviceCalendarService.fetchEvents(start: start, end: end, calendarId: id, includeAll: false);
        events.addAll(ev);
      }
    } else {
      events.addAll(await DeviceCalendarService.fetchEvents(start: start, end: end));
    }

    final db = await AppDb.instance;
    final scanned = events.length;
    int imported = 0;
    int skippedExisting = 0;
    int unmatched = 0;

    // Build quick lookup for people by normalized name and phone
    final peopleRows = await db.query('person');
    String norm(String s) => s.trim().toLowerCase().replaceAll(RegExp(r"\s+"), ' ');
    String normPhone(String s) => s.replaceAll(RegExp(r'[^0-9+]'), '');
    final byName = <String, Map<String, Object?>>{};
    final byPhone = <String, Map<String, Object?>>{};
    for (final p in peopleRows) {
      final name = (p['name'] as String?) ?? '';
      if (name.isNotEmpty) byName[norm(name)] = p;
      final phone = (p['phone'] as String?) ?? '';
      if (phone.isNotEmpty) byPhone[normPhone(phone)] = p;
    }

    await db.transaction((txn) async {
      for (final e in events) {
        try {
          final calId = e.calendarId ?? 'unknown';
          String fallbackIdPart = '${e.title ?? ''}|${e.start?.millisecondsSinceEpoch ?? 0}|${e.end?.millisecondsSinceEpoch ?? 0}|${e.location ?? ''}';
          final extId = 'device:$calId:${e.eventId ?? fallbackIdPart}';

          // Skip if already imported
          final exists = sql.Sqflite.firstIntValue(await txn.rawQuery('SELECT 1 FROM interaction WHERE externalId=? LIMIT 1', [extId])) == 1;
          if (exists) {
            skippedExisting++;
            continue;
          }

          // Try match by attendees' emails/phones or event title
          Map<String, Object?>? person;
          // attempt by phone in description/location
          final blob = ('${e.description ?? ''} ${e.location ?? ''}').toLowerCase();
          for (final entry in byPhone.entries) {
            if (blob.contains(entry.key)) {
              person = entry.value;
              break;
            }
          }
          if (person == null) {
            final title = norm(e.title ?? '');
            if (byName.containsKey(title)) person = byName[title];
          }

          if (person == null) {
            unmatched++;
            continue; // Skip unmatched for now; UI can offer preview/choice later
          }

          final personId = person['id'] as int;
          final at = (e.start ?? e.end ?? DateTime.now()).millisecondsSinceEpoch;
          await txn.insert('interaction', {
            'personId': personId,
            'at': at,
            'type': 'calendar',
            'initiator': 'them',
            'note': e.title,
            'externalId': extId,
          }, conflictAlgorithm: sql.ConflictAlgorithm.ignore);

          // Update person's lastInteractionAt if newer
          await txn.rawUpdate(
            'UPDATE person SET lastInteractionAt = MAX(COALESCE(lastInteractionAt,0), ?) WHERE id=?',
            [at, personId],
          );

          imported++;
        } catch (err, st) {
          if (kDebugMode) debugPrint('Import error: $err\n$st');
        }
      }
    });

    return CalendarImportSummary(
      scanned: scanned,
      imported: imported,
      skippedExisting: skippedExisting,
      unmatched: unmatched,
    );
  }
}
