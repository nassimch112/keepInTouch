// Placeholder DB service using sqflite
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models.dart';

class AppDb {
  static Database? _db;
  static Future<Database> get instance async {
    if (_db != null) return _db!;
    final path = p.join(await getDatabasesPath(), 'keepintouch.db');
    _db = await openDatabase(path, version: 4, onCreate: (db, v) async {
      await db.execute('''
        CREATE TABLE person(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          phone TEXT,
          tags TEXT,
          cadenceDays INTEGER NOT NULL,
          preferredStart INTEGER,
          preferredEnd INTEGER,
          preferredDays TEXT,
          notes TEXT,
          lastInteractionAt INTEGER,
          snoozeUntil INTEGER,
          favorite INTEGER NOT NULL DEFAULT 0
        );
      ''');
      await db.execute('''
        CREATE TABLE interaction(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          personId INTEGER NOT NULL,
          at INTEGER NOT NULL,
          type TEXT NOT NULL,
          initiator TEXT NOT NULL,
          note TEXT,
          externalId TEXT,
          FOREIGN KEY(personId) REFERENCES person(id) ON DELETE CASCADE
        );
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_interaction_person_at ON interaction(personId, at DESC)');
      await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_interaction_externalId ON interaction(externalId)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_person_last_at ON person(lastInteractionAt DESC)');
      await db.execute('''
        CREATE TABLE special_date(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          personId INTEGER NOT NULL,
          type TEXT NOT NULL,
          date INTEGER NOT NULL,
          remindDays TEXT,
          FOREIGN KEY(personId) REFERENCES person(id) ON DELETE CASCADE
        );
      ''');
    }, onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 2) {
        // Add initiator column, default to 'me' for existing rows
        await db.execute("ALTER TABLE interaction ADD COLUMN initiator TEXT NOT NULL DEFAULT 'me'");
      }
      if (oldVersion < 3) {
        await db.execute("ALTER TABLE person ADD COLUMN favorite INTEGER NOT NULL DEFAULT 0");
        await db.execute('CREATE INDEX IF NOT EXISTS idx_interaction_person_at ON interaction(personId, at DESC)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_person_last_at ON person(lastInteractionAt DESC)');
      }
      if (oldVersion < 4) {
        await db.execute('ALTER TABLE interaction ADD COLUMN externalId TEXT');
        await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_interaction_externalId ON interaction(externalId)');
      }
    });
    return _db!;
  }
}

class PersonRepo {
  final Database db;
  PersonRepo(this.db);

  Future<int> add(Person p) async {
    return await db.insert('person', p.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> update(Person p) async {
    if (p.id == null) throw ArgumentError('Person id is null');
    return await db.update('person', p.toMap(), where: 'id=?', whereArgs: [p.id]);
  }

  Future<void> delete(int id) async {
    await db.delete('person', where: 'id=?', whereArgs: [id]);
  }

  Future<List<Person>> all() async {
    final rows = await db.query('person', orderBy: 'name ASC');
    return rows.map((e) => PersonMap.fromMap(e)).toList();
  }

  Future<void> markDone(int id, {String initiator = 'me'}) async {
    final now = DateTime.now();
    await db.update('person', {'lastInteractionAt': now.millisecondsSinceEpoch, 'snoozeUntil': null}, where: 'id=?', whereArgs: [id]);
    await db.insert('interaction', {
      'personId': id,
      'at': now.millisecondsSinceEpoch,
      'type': 'touch',
      'initiator': initiator,
      'note': null,
    });
  }

  Future<void> snooze(int id, Duration d) async {
    final until = DateTime.now().add(d).millisecondsSinceEpoch;
    await db.update('person', {'snoozeUntil': until}, where: 'id=?', whereArgs: [id]);
  }

  Future<List<Person>> dueNow({DateTime? now}) async {
    now ??= DateTime.now();
    final rows = await db.query('person');
    final people = rows.map((e) => PersonMap.fromMap(e)).toList();
    return people.where((p) {
      if (p.snoozeUntil != null && p.snoozeUntil!.isAfter(now!)) return false;
      final last = p.lastInteractionAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final nextDue = last.add(Duration(days: p.cadenceDays));
      return !nextDue.isAfter(now!);
    }).toList();
  }

  Future<List<Person>> upcoming({DateTime? now}) async {
    now ??= DateTime.now();
    final rows = await db.query('person');
    final people = rows.map((e) => PersonMap.fromMap(e)).toList();
    return people.where((p) {
      if (p.snoozeUntil != null && p.snoozeUntil!.isAfter(now!)) return false;
      final last = p.lastInteractionAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final nextDue = last.add(Duration(days: p.cadenceDays));
      final within7 = now!.add(const Duration(days: 7));
      return nextDue.isAfter(now) && !nextDue.isAfter(within7);
    }).toList();
  }
}
