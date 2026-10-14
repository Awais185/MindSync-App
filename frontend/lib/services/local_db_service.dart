import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/app_user.dart';
import '../models/local_auth_record.dart';

/// Local SQLite (or prefs on web) — primary store for login.
class LocalDbService {
  LocalDbService._();
  static final LocalDbService instance = LocalDbService._();

  static const _dbName = 'mindsync_users.db';
  static const _dbVersion = 2;
  static const _tableUsers = 'users';
  static const _prefsUsersKey = 'mindsync.local_users.v2';
  static const _prefsUsersKeyV1 = 'mindsync.local_users.v1';

  Database? _db;
  bool? _prefsOnly;
  bool _migrationDone = false;

  /// Loads legacy v1 prefs into v2 and normalizes email casing.
  Future<void> ensureMigrated() async {
    if (_migrationDone) return;
    _migrationDone = true;

    if (await _usesPrefsOnly()) {
      final prefs = await SharedPreferences.getInstance();
      final v1 = prefs.getString(_prefsUsersKeyV1);
      if (v1 == null || v1.isEmpty) return;

      final records = await _readPrefsRecords();
      try {
        final decoded = jsonDecode(v1) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          final row = Map<String, dynamic>.from(entry.value as Map);
          row['passwordHash'] ??= '';
          row['isGoogleAccount'] ??= 0;
          final record = _rowToRecord(row);
          final email = record.user.email.trim().toLowerCase();
          final user = record.user.copyWith(email: email);
          records[user.uid] = LocalAuthRecord(
            user: user,
            passwordHash: record.passwordHash,
            isGoogleAccount: record.isGoogleAccount,
          );
        }
        await _writePrefsRecords(records);
      } catch (e) {
        debugPrint('LocalDbService: v1 migration failed: $e');
      }
    }
  }

  Future<bool> _usesPrefsOnly() async {
    if (_prefsOnly != null) return _prefsOnly!;
    if (kIsWeb) {
      _prefsOnly = true;
      return true;
    }
    try {
      await getDatabasesPath();
      _prefsOnly = false;
    } on Object {
      _prefsOnly = true;
    }
    return _prefsOnly!;
  }

  Future<Database> get database async {
    if (await _usesPrefsOnly()) {
      throw UnsupportedError('SQLite not available; using SharedPreferences.');
    }
    if (_db != null) return _db!;
    _db = await _openDatabase();
    return _db!;
  }

  Future<Database> _openDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await _createUsersTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE $_tableUsers ADD COLUMN passwordHash TEXT NOT NULL DEFAULT ""',
          );
          await db.execute(
            'ALTER TABLE $_tableUsers ADD COLUMN isGoogleAccount INTEGER NOT NULL DEFAULT 0',
          );
        }
      },
    );
  }

  Future<void> _createUsersTable(Database db) async {
    await db.execute('''
      CREATE TABLE $_tableUsers (
        uid TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        email TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        firstName TEXT NOT NULL DEFAULT '',
        lastName TEXT NOT NULL DEFAULT '',
        username TEXT NOT NULL DEFAULT '',
        profession TEXT NOT NULL DEFAULT 'other',
        faceImage TEXT NOT NULL DEFAULT '',
        faceEnrolled INTEGER NOT NULL DEFAULT 0,
        isDoctor INTEGER NOT NULL DEFAULT 0,
        passwordHash TEXT NOT NULL DEFAULT '',
        isGoogleAccount INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Map<String, dynamic> _recordToRow(LocalAuthRecord record) {
    final map = record.user.toMap();
    map['passwordHash'] = record.passwordHash;
    map['isGoogleAccount'] = record.isGoogleAccount ? 1 : 0;
    return map;
  }

  LocalAuthRecord _rowToRecord(Map<String, dynamic> row) {
    return LocalAuthRecord(
      user: AppUser.fromMap(row),
      passwordHash: (row['passwordHash'] as String?) ?? '',
      isGoogleAccount: row['isGoogleAccount'] == 1 || row['isGoogleAccount'] == true,
    );
  }

  Future<Map<String, LocalAuthRecord>> _readPrefsRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsUsersKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map(
        (key, value) => MapEntry(
          key,
          _rowToRecord(Map<String, dynamic>.from(value as Map)),
        ),
      );
    } catch (e) {
      debugPrint('LocalDbService: failed to parse prefs users: $e');
      return {};
    }
  }

  Future<void> _writePrefsRecords(Map<String, LocalAuthRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = records.map((k, v) => MapEntry(k, _recordToRow(v)));
    await prefs.setString(_prefsUsersKey, jsonEncode(encoded));
  }

  Future<void> saveUserWithPassword(
    AppUser user, {
    required String passwordHash,
    bool isGoogleAccount = false,
  }) async {
    final record = LocalAuthRecord(
      user: user,
      passwordHash: passwordHash,
      isGoogleAccount: isGoogleAccount,
    );

    if (await _usesPrefsOnly()) {
      final records = await _readPrefsRecords();
      records[user.uid] = record;
      await _writePrefsRecords(records);
      return;
    }

    final db = await database;
    await db.insert(
      _tableUsers,
      _recordToRow(record),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> saveUser(AppUser user) async {
    final existing = await getUser(user.uid);
    await saveUserWithPassword(
      user,
      passwordHash: existing?.passwordHash ?? '',
      isGoogleAccount: existing?.isGoogleAccount ?? false,
    );
  }

  Future<LocalAuthRecord?> getUser(String uid) async {
    if (await _usesPrefsOnly()) {
      final records = await _readPrefsRecords();
      return records[uid];
    }

    final db = await database;
    final rows = await db.query(
      _tableUsers,
      where: 'uid = ?',
      whereArgs: [uid],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _rowToRecord(rows.first);
  }

  Future<LocalAuthRecord?> getUserByEmail(String email) async {
    await ensureMigrated();
    final normalized = email.trim().toLowerCase();
    if (await _usesPrefsOnly()) {
      for (final record in (await _readPrefsRecords()).values) {
        if (record.user.email.trim().toLowerCase() == normalized) {
          return record;
        }
      }
      return null;
    }

    final db = await database;
    var rows = await db.query(
      _tableUsers,
      where: 'LOWER(email) = ?',
      whereArgs: [normalized],
      limit: 1,
    );
    if (rows.isEmpty) {
      rows = await db.query(
        _tableUsers,
        where: 'email = ?',
        whereArgs: [normalized],
        limit: 1,
      );
    }
    if (rows.isEmpty) {
      final all = await db.query(_tableUsers);
      for (final row in all) {
        final e = (row['email'] as String?)?.trim().toLowerCase() ?? '';
        if (e == normalized) return _rowToRecord(row);
      }
      return null;
    }
    return _rowToRecord(rows.first);
  }

  Future<List<LocalAuthRecord>> getAllUsers() async {
    if (await _usesPrefsOnly()) {
      return (await _readPrefsRecords()).values.toList();
    }

    final db = await database;
    final rows = await db.query(_tableUsers);
    return rows.map(_rowToRecord).toList();
  }

  Future<void> updatePasswordHash(String uid, String passwordHash) async {
    final record = await getUser(uid);
    if (record == null) return;
    await saveUserWithPassword(
      record.user,
      passwordHash: passwordHash,
      isGoogleAccount: record.isGoogleAccount,
    );
  }

  Future<void> deleteUser(String uid) async {
    if (await _usesPrefsOnly()) {
      final records = await _readPrefsRecords();
      records.remove(uid);
      await _writePrefsRecords(records);
      return;
    }

    final db = await database;
    await db.delete(_tableUsers, where: 'uid = ?', whereArgs: [uid]);
  }

  Future<void> clearAllUsers() async {
    if (await _usesPrefsOnly()) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsUsersKey);
      return;
    }

    final db = await database;
    await db.delete(_tableUsers);
  }
}
