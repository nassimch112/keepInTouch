class Person {
  final int? id;
  final String name;
  final String? phone;
  final List<String> tags;
  final int cadenceDays; // e.g., 7/14/30
  final TimeWindow? preferredWindow;
  final String? notes;
  final List<SpecialDate> specialDates;
  final DateTime? lastInteractionAt;
  final DateTime? snoozeUntil;
  final bool favorite;

  Person({
    this.id,
    required this.name,
    this.phone,
    this.tags = const [],
    required this.cadenceDays,
    this.preferredWindow,
    this.notes,
    this.specialDates = const [],
    this.lastInteractionAt,
    this.snoozeUntil,
    this.favorite = false,
  });
}

class Interaction {
  final int? id;
  final int personId;
  final DateTime at;
  final String type; // call|sms|meet|other
  final String? note;

  Interaction({this.id, required this.personId, required this.at, required this.type, this.note});
}

class Reminder {
  final int? id;
  final int personId;
  final DateTime dueAt;
  final String status; // scheduled|snoozed|done|skipped

  Reminder({this.id, required this.personId, required this.dueAt, required this.status});
}

class SettingsModel {
  final TimeWindow quietHours;
  final BatchSlot batchSlot;
  final bool calendarEnabled;

  SettingsModel({required this.quietHours, required this.batchSlot, this.calendarEnabled = false});
}

class TimeWindow {
  final int startMinutes; // minutes since midnight
  final int endMinutes;
  final List<int> daysOfWeek; // 0..6 (Sun..Sat)
  const TimeWindow({required this.startMinutes, required this.endMinutes, this.daysOfWeek = const [0,1,2,3,4,5,6]});
}

class BatchSlot {
  final int dayOfWeek; // 0..6
  final int startMinutes;
  final int endMinutes;
  const BatchSlot({required this.dayOfWeek, required this.startMinutes, required this.endMinutes});
}

class SpecialDate {
  final String type; // birthday|anniversary|custom
  final DateTime date; // yyyy-mm-dd date
  final List<int> remindDaysBefore;
  const SpecialDate({required this.type, required this.date, this.remindDaysBefore = const [1]});
}

// Simple mapping helpers (only fields we persist in v1)
extension PersonMap on Person {
  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'tags': tags.join(','),
      'cadenceDays': cadenceDays,
      'preferredStart': preferredWindow?.startMinutes,
      'preferredEnd': preferredWindow?.endMinutes,
      'preferredDays': preferredWindow?.daysOfWeek.join(','),
      'notes': notes,
      'lastInteractionAt': lastInteractionAt?.millisecondsSinceEpoch,
      'snoozeUntil': snoozeUntil?.millisecondsSinceEpoch,
      'favorite': favorite ? 1 : 0,
    };
  }

  static Person fromMap(Map<String, Object?> m) {
    TimeWindow? win;
    final start = m['preferredStart'] as int?;
    final end = m['preferredEnd'] as int?;
    final daysCsv = m['preferredDays'] as String?;
    if (start != null && end != null) {
      win = TimeWindow(
        startMinutes: start,
        endMinutes: end,
        daysOfWeek: daysCsv == null || daysCsv.isEmpty
            ? const [0, 1, 2, 3, 4, 5, 6]
            : daysCsv.split(',').map((e) => int.tryParse(e) ?? 0).toList(),
      );
    }
    final tagsCsv = (m['tags'] as String?) ?? '';
    return Person(
      id: (m['id'] as int?),
      name: (m['name'] as String?) ?? '',
      phone: m['phone'] as String?,
      tags: tagsCsv.isEmpty ? const [] : tagsCsv.split(',').toList(),
      cadenceDays: (m['cadenceDays'] as int?) ?? 30,
      preferredWindow: win,
      notes: m['notes'] as String?,
      lastInteractionAt: (m['lastInteractionAt'] as int?) != null
          ? DateTime.fromMillisecondsSinceEpoch(m['lastInteractionAt'] as int)
          : null,
      snoozeUntil: (m['snoozeUntil'] as int?) != null
          ? DateTime.fromMillisecondsSinceEpoch(m['snoozeUntil'] as int)
          : null,
      favorite: ((m['favorite'] as int?) ?? 0) == 1,
    );
  }
}
