import 'dart:async';
import 'package:device_calendar/device_calendar.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';

class DeviceCalendarService {
  static final DeviceCalendarPlugin _plugin = DeviceCalendarPlugin();

  static Future<bool> ensurePermissions() async {
    // First, ask the plugin if it already has permissions
    try {
      final has = await _plugin.hasPermissions();
      if (has.isSuccess && (has.data ?? false)) return true;
    } catch (_) {}

    // Try permission_handler for a unified UX on Android/iOS
    final fullStatus = await Permission.calendarFullAccess.request();
    if (fullStatus.isGranted) return true;
    final writeOnly = await Permission.calendarWriteOnly.request();
    if (writeOnly.isGranted) return true;
    if (fullStatus.isPermanentlyDenied || writeOnly.isPermanentlyDenied) {
      if (kDebugMode) debugPrint('Calendar permission permanently denied');
      return false;
    }

    // Fall back to the plugin's own request flow
    try {
      final res = await _plugin.requestPermissions();
      if (res.isSuccess && (res.data ?? false)) return true;
      // Double-check after request
      final has = await _plugin.hasPermissions();
      return has.isSuccess && (has.data ?? false);
    } catch (_) {
      return false;
    }
  }

  static Future<List<Calendar>> listCalendars() async {
    final result = await _plugin.retrieveCalendars();
    if (!result.isSuccess) return const [];
    return result.data ?? const [];
  }

  static Future<List<Event>> fetchEvents({
    required DateTime start,
    required DateTime end,
    String? calendarId,
    bool includeAll = true,
  }) async {
    final params = RetrieveEventsParams(startDate: start, endDate: end);
    final List<Calendar> cals = calendarId != null
        ? [Calendar(id: calendarId)]
        : (includeAll ? await listCalendars() : <Calendar>[]);
    final events = <Event>[];
    for (final cal in cals) {
      if (cal.id == null) continue;
      final res = await _plugin.retrieveEvents(cal.id!, params);
      if (res.isSuccess && res.data != null) {
        events.addAll(res.data!);
      }
    }
    return events;
  }
}
