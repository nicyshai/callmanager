import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

enum LogCategory { sqlite, socket, callkit, state, system, error }

class LogEntry {
  final DateTime timestamp;
  final LogCategory category;
  final String message;

  LogEntry({
    required this.timestamp,
    required this.category,
    required this.message,
  });

  String get timeString {
    final hh = timestamp.hour.toString().padLeft(2, '0');
    final mm = timestamp.minute.toString().padLeft(2, '0');
    final ss = timestamp.second.toString().padLeft(2, '0');
    final ms = (timestamp.millisecond).toString().padLeft(3, '0');
    return '$hh:$mm:$ss.$ms';
  }
}

class AppLogger {
  static final List<LogEntry> _history = [];
  static final List<void Function(LogEntry)> _listeners = [];

  static List<LogEntry> get history => List.unmodifiable(_history);

  static void addListener(void Function(LogEntry) listener) {
    _listeners.add(listener);
    // Deliver history to new listener asynchronously to avoid modifying providers during build
    Future.microtask(() {
      for (final entry in _history) {
        listener(entry);
      }
    });
  }

  static void removeListener(void Function(LogEntry) listener) {
    _listeners.remove(listener);
  }

  static void log(LogCategory category, String message) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      category: category,
      message: message,
    );
    
    _history.add(entry);
    if (_history.length > 500) {
      _history.removeAt(0);
    }

    // Also write to standard Dart print console
    final label = category.name.toUpperCase().padRight(7);
    print('[$label] ${entry.timeString} | $message');

    for (final listener in List.from(_listeners)) {
      try {
        listener(entry);
      } catch (e) {
        // Safe fail if listener errors
      }
    }
  }

  static void sqlite(String message) => log(LogCategory.sqlite, message);
  static void socket(String message) => log(LogCategory.socket, message);
  static void callkit(String message) => log(LogCategory.callkit, message);
  static void state(String message) => log(LogCategory.state, message);
  static void system(String message) => log(LogCategory.system, message);
  static void error(String message) => log(LogCategory.error, message);
  static void clear() {
    _history.clear();
    log(LogCategory.system, "Logs cleared");
  }
}

class LogNotifier extends StateNotifier<List<LogEntry>> {
  LogNotifier() : super([]) {
    AppLogger.addListener(_onLog);
  }

  void _onLog(LogEntry entry) {
    if (state.length > 500) {
      state = [...state.sublist(state.length - 490), entry];
    } else {
      state = [...state, entry];
    }
  }

  void clearLogs() {
    AppLogger.clear();
    state = [];
  }

  @override
  void dispose() {
    AppLogger.removeListener(_onLog);
    super.dispose();
  }
}

final logProvider = StateNotifierProvider<LogNotifier, List<LogEntry>>((ref) {
  return LogNotifier();
});
