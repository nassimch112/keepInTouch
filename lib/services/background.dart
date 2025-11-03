import 'package:workmanager/workmanager.dart';
import 'notifications.dart';
import 'settings.dart';
import 'db.dart';
import 'package:flutter/material.dart';

const dailyTask = 'daily-reminder-check';
const weeklyBatchTask = 'weekly-batch-reminder';

@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    // Load settings
  await SettingsService.getDailyReminderTime();
    final perPerson = await SettingsService.getPerPersonNudges();

    // Compute due list
    final db = await AppDb.instance;
    final repo = PersonRepo(db);
    final due = await repo.dueNow(now: DateTime.now());

    // Summary notification
    if (due.isNotEmpty) {
      await Notifier.showSummary(due.length);
    }

    // Optional per-person nudges (cap 5)
    if (perPerson && due.isNotEmpty) {
      for (final p in due.take(5)) {
        await Notifier.showPersonNudge(personId: p.id!, name: p.name);
      }
    }
    return true;
  });
}

class BackgroundScheduler {
  static Future<void> init() async {
    await Workmanager().initialize(backgroundDispatcher, isInDebugMode: false);
  }

  static Future<void> scheduleDaily() async {
    // Re-register daily task
    await Workmanager().cancelByUniqueName('daily');
    await Workmanager().registerPeriodicTask('daily', dailyTask, frequency: const Duration(hours: 24));
  }

  static Future<void> scheduleDailyAt(TimeOfDay time) async {
    // WorkManager periodic doesn't support exact time; use initialDelay to align roughly
    // and let Android batch within flex. We'll re-register daily on app start to keep aligned.
    final now = DateTime.now();
    var first = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    if (!first.isAfter(now)) first = first.add(const Duration(days: 1));
    final initialDelay = first.difference(now);
    await Workmanager().cancelByUniqueName('daily');
    await Workmanager().registerPeriodicTask(
      'daily',
      dailyTask,
      frequency: const Duration(hours: 24),
      initialDelay: initialDelay,
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );
  }
}
