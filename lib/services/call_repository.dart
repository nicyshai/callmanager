import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../core/logger.dart';
import '../models/call_model.dart';

class InvalidStateTransitionException implements Exception {
  final String callId;
  final CallState from;
  final CallState to;

  InvalidStateTransitionException(this.callId, this.from, this.to);

  @override
  String toString() =>
      'InvalidStateTransitionException: Call $callId cannot transition from ${from.name} to ${to.name}';
}

abstract class CallRepository {
  Future<void> init();
  Future<CallModel?> getCall(String callId);
  Future<CallModel> createCall(CallModel call);
  Future<CallModel> updateCallState(String callId, CallState newState);
  Future<List<CallModel>> getCallHistory();
  Future<void> recoverActiveCalls();
  Future<void> clearAll();
}

/// SQLite Implementation of [CallRepository] with In-Memory fallback
class SqliteCallRepository implements CallRepository {
  Database? _db;
  bool _useFallback = false;
  final InMemoryCallRepository _fallback = InMemoryCallRepository();

  Future<Database> get _database async {
    if (_db != null) return _db!;
    throw StateError("Database not initialized. Call init() first.");
  }

  @override
  Future<void> init() async {
    // 1. Platform compatibility check
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) {
      AppLogger.system("Non-supported SQLite platform. Falling back to In-Memory Database.");
      _useFallback = true;
      await _fallback.init();
      return;
    }

    if (_db != null && _db!.isOpen) {
      AppLogger.sqlite("SQLite database already open and initialized");
      return;
    }
    
    try {
      final databasesPath = await getDatabasesPath();
      final path = p.join(databasesPath, 'call_manager.db');

      AppLogger.sqlite("Opening SQLite database at $path");
      _db = await openDatabase(
        path,
        version: 1,
        onCreate: (Database db, int version) async {
          await db.execute('''
            CREATE TABLE calls (
              call_id TEXT PRIMARY KEY,
              caller_id TEXT NOT NULL,
              receiver_id TEXT NOT NULL,
              state TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
          AppLogger.sqlite("Created calls table in SQLite");
        },
      );
      AppLogger.sqlite("SQLite database initialized successfully");
    } catch (e) {
      AppLogger.error("Failed to initialize SQLite: $e. Falling back to In-Memory Database.");
      _useFallback = true;
      await _fallback.init();
    }
  }

  @override
  Future<CallModel?> getCall(String callId) async {
    if (_useFallback) return _fallback.getCall(callId);

    try {
      final db = await _database;
      final List<Map<String, dynamic>> maps = await db.query(
        'calls',
        where: 'call_id = ?',
        whereArgs: [callId],
      );

      if (maps.isEmpty) return null;
      return CallModel.fromMap(maps.first);
    } catch (e) {
      AppLogger.error("Error fetching call $callId: $e");
      rethrow;
    }
  }

  @override
  Future<CallModel> createCall(CallModel call) async {
    if (_useFallback) return _fallback.createCall(call);

    try {
      final db = await _database;
      
      // Use transactional insert to be fully atomic
      return await db.transaction((txn) async {
        final List<Map<String, dynamic>> existing = await txn.query(
          'calls',
          where: 'call_id = ?',
          whereArgs: [call.callId],
        );

        if (existing.isNotEmpty) {
          final existingCall = CallModel.fromMap(existing.first);
          AppLogger.sqlite("Duplicate create Call blocked for call_id: ${call.callId}. Returning existing call.");
          return existingCall;
        }

        await txn.insert('calls', call.toMap());
        AppLogger.sqlite("Inserted Call record: ${call.callId} with state: ${call.state.name}");
        final count = Sqflite.firstIntValue(await txn.rawQuery('SELECT COUNT(*) FROM calls'));
        AppLogger.sqlite("Current total records in DB: $count");
        return call;
      });
    } catch (e) {
      AppLogger.error("Error creating call ${call.callId}: $e");
      rethrow;
    }
  }

  @override
  Future<CallModel> updateCallState(String callId, CallState newState) async {
    if (_useFallback) return _fallback.updateCallState(callId, newState);

    try {
      final db = await _database;

      return await db.transaction((txn) async {
        final List<Map<String, dynamic>> maps = await txn.query(
          'calls',
          where: 'call_id = ?',
          whereArgs: [callId],
        );

        if (maps.isEmpty) {
          throw Exception("Call not found in database: $callId");
        }

        final currentCall = CallModel.fromMap(maps.first);
        final currentState = currentCall.state;

        // Idempotency: target state is same as current state
        if (currentState == newState) {
          return currentCall;
        }

        // Validate state transition rules
        if (!currentState.canTransitionTo(newState)) {
          AppLogger.sqlite("BLOCKED invalid state transition for $callId: ${currentState.name} -> ${newState.name}");
          throw InvalidStateTransitionException(callId, currentState, newState);
        }

        final updatedCall = currentCall.copyWith(
          state: newState,
          updatedAt: DateTime.now(),
        );

        await txn.update(
          'calls',
          updatedCall.toMap(),
          where: 'call_id = ?',
          whereArgs: [callId],
        );

        AppLogger.sqlite("Transitioned $callId from ${currentState.name} to ${newState.name}");
        return updatedCall;
      });
    } catch (e) {
      if (e is InvalidStateTransitionException) {
        rethrow;
      }
      AppLogger.error("Error updating call state for $callId to ${newState.name}: $e");
      rethrow;
    }
  }

  @override
  Future<List<CallModel>> getCallHistory() async {
    if (_useFallback) return _fallback.getCallHistory();

    try {
      final db = await _database;
      final List<Map<String, dynamic>> maps = await db.query(
        'calls',
        orderBy: 'created_at DESC',
      );
      AppLogger.sqlite("Fetched ${maps.length} records from history");
      return maps.map((m) => CallModel.fromMap(m)).toList();
    } catch (e) {
      AppLogger.error("Error fetching call history: $e");
      return [];
    }
  }

  @override
  Future<void> recoverActiveCalls() async {
    if (_useFallback) return _fallback.recoverActiveCalls();

    try {
      final db = await _database;
      await db.transaction((txn) async {
        final List<Map<String, dynamic>> activeMaps = await txn.query(
          'calls',
          where: 'state NOT IN (?, ?, ?, ?)',
          whereArgs: [
            CallState.ended.name,
            CallState.rejected.name,
            CallState.cancelled.name,
            CallState.failed.name,
          ],
        );

        if (activeMaps.isNotEmpty) {
          AppLogger.sqlite("Restart Recovery: Found ${activeMaps.length} active calls. Resolving to FAILED.");
          for (final map in activeMaps) {
            final callId = map['call_id'] as String;
            final oldState = map['state'] as String;
            AppLogger.sqlite("Recovering call $callId (state: $oldState) -> FAILED");
            
            await txn.update(
              'calls',
              {
                'state': CallState.failed.name,
                'updated_at': DateTime.now().millisecondsSinceEpoch,
              },
              where: 'call_id = ?',
              whereArgs: [callId],
            );
          }
        } else {
          AppLogger.sqlite("Restart Recovery: No active calls requiring cleanup.");
        }
      });
    } catch (e) {
      AppLogger.error("Error recovering active calls: $e");
    }
  }

  @override
  Future<void> clearAll() async {
    if (_useFallback) return _fallback.clearAll();

    try {
      final db = await _database;
      await db.delete('calls');
      AppLogger.sqlite("SQLite database call records cleared");
    } catch (e) {
      AppLogger.error("Error clearing database: $e");
    }
  }
}

/// InMemory Implementation of [CallRepository] for unit tests or fallback
class InMemoryCallRepository implements CallRepository {
  final Map<String, CallModel> _db = {};

  @override
  Future<void> init() async {
    AppLogger.sqlite("In-Memory database initialized");
  }

  @override
  Future<CallModel?> getCall(String callId) async {
    return _db[callId];
  }

  @override
  Future<CallModel> createCall(CallModel call) async {
    if (_db.containsKey(call.callId)) {
      final existingCall = _db[call.callId]!;
      AppLogger.sqlite("Duplicate create Call blocked for call_id: ${call.callId} (In-Memory)");
      return existingCall;
    }
    _db[call.callId] = call;
    AppLogger.sqlite("Inserted Call record: ${call.callId} with state: ${call.state.name} (In-Memory)");
    return call;
  }

  @override
  Future<CallModel> updateCallState(String callId, CallState newState) async {
    if (!_db.containsKey(callId)) {
      throw Exception("Call not found in database: $callId");
    }

    final currentCall = _db[callId]!;
    final currentState = currentCall.state;

    if (currentState == newState) {
      return currentCall;
    }

    if (!currentState.canTransitionTo(newState)) {
      AppLogger.sqlite("BLOCKED invalid state transition for $callId: ${currentState.name} -> ${newState.name} (In-Memory)");
      throw InvalidStateTransitionException(callId, currentState, newState);
    }

    final updatedCall = currentCall.copyWith(
      state: newState,
      updatedAt: DateTime.now(),
    );

    _db[callId] = updatedCall;
    AppLogger.sqlite("Transitioned $callId from ${currentState.name} to ${newState.name} (In-Memory)");
    return updatedCall;
  }

  @override
  Future<List<CallModel>> getCallHistory() async {
    final list = _db.values.toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  @override
  Future<void> recoverActiveCalls() async {
    final activeKeys = _db.keys.where((k) {
      final state = _db[k]!.state;
      return !state.isTerminal;
    }).toList();

    if (activeKeys.isNotEmpty) {
      AppLogger.sqlite("Restart Recovery: Found ${activeKeys.length} active calls (In-Memory). Resolving to FAILED.");
      for (final key in activeKeys) {
        final current = _db[key]!;
        AppLogger.sqlite("Recovering call $key (state: ${current.state.name}) -> FAILED");
        _db[key] = current.copyWith(
          state: CallState.failed,
          updatedAt: DateTime.now(),
        );
      }
    }
  }

  @override
  Future<void> clearAll() async {
    _db.clear();
    AppLogger.sqlite("In-Memory database call records cleared");
  }
}

/// Riverpod provider for the [CallRepository]
final callRepositoryProvider = Provider<CallRepository>((ref) {
  // Default is SqliteCallRepository, but we can switch or handle errors
  return SqliteCallRepository();
});
