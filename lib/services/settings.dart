import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const _kDailyHour = 'dailyHour';
  static const _kDailyMinute = 'dailyMinute';
  static const _kPerPerson = 'perPersonNudges';
  static const _kCompact = 'compactDensity';
  static const _kBgColor = 'bgColor';
  static const _kCardColor = 'cardColor';
  static const _kHaptics = 'hapticsEnabled';
  static const _kDeviceCalendar = 'deviceCalendarEnabled';

  static Future<TimeOfDay> getDailyReminderTime() async {
    final sp = await SharedPreferences.getInstance();
    final h = sp.getInt(_kDailyHour);
    final m = sp.getInt(_kDailyMinute);
    if (h == null || m == null) return const TimeOfDay(hour: 19, minute: 30);
    return TimeOfDay(hour: h, minute: m);
  }

  static Future<void> setDailyReminderTime(TimeOfDay t) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_kDailyHour, t.hour);
    await sp.setInt(_kDailyMinute, t.minute);
  }

  static Future<bool> getPerPersonNudges() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_kPerPerson) ?? true;
  }

  static Future<void> setPerPersonNudges(bool v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kPerPerson, v);
  }

  static Future<bool> getCompactDensity() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_kCompact) ?? false;
  }

  static Future<void> setCompactDensity(bool v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kCompact, v);
  }

  // Theme colors
  static Future<(Color, Color)> getThemeColors() async {
    final sp = await SharedPreferences.getInstance();
    final bg = sp.getInt(_kBgColor);
    final card = sp.getInt(_kCardColor);
    return (
      Color(bg ?? 0xFF0f172a),
      Color(card ?? 0xFF111827),
    );
  }

  static Future<void> setThemeColors({required Color background, required Color card}) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_kBgColor, background.toARGB32());
    await sp.setInt(_kCardColor, card.toARGB32());
  }

  // Haptics
  static Future<bool> getHapticsEnabled() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_kHaptics) ?? true;
  }
  static Future<void> setHapticsEnabled(bool v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kHaptics, v);
  }

  // Device calendar toggle
  static Future<bool> getDeviceCalendarEnabled() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_kDeviceCalendar) ?? false;
  }
  static Future<void> setDeviceCalendarEnabled(bool v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kDeviceCalendar, v);
  }
}
