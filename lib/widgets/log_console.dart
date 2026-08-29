import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/logger.dart';
import '../core/theme.dart';

class LogConsole extends ConsumerStatefulWidget {
  const LogConsole({super.key});

  @override
  ConsumerState<LogConsole> createState() => _LogConsoleState();
}

class _LogConsoleState extends ConsumerState<LogConsole> {
  final ScrollController _scrollController = ScrollController();

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
  }

  Color _getCategoryColor(LogCategory cat) {
    switch (cat) {
      case LogCategory.sqlite:
        return Colors.purpleAccent;
      case LogCategory.socket:
        return AppColors.info;
      case LogCategory.callkit:
        return AppColors.success;
      case LogCategory.state:
        return AppColors.warning;
      case LogCategory.system:
        return AppColors.textSecondary;
      case LogCategory.error:
        return AppColors.error;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(logProvider);

    // Trigger auto scroll to end
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    return Container(
      height: 240,
      decoration: AppTheme.glassBox(
        color: AppColors.background,
        radius: 12,
        borderColor: AppColors.border,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
              border: Border(
                bottom: BorderSide(color: AppColors.border, width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.terminal, color: AppColors.info, size: 18),
                    SizedBox(width: 8),
                    Text(
                      "LIVE SYSTEM LOG CONSOLE",
                      style: TextStyle(
                        fontFamily: "monospace",
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.delete_sweep_outlined, color: AppColors.textMuted, size: 18),
                  onPressed: () {
                    ref.read(logProvider.notifier).clearLogs();
                  },
                  tooltip: "Clear Logs",
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          
          // Log List
          Expanded(
            child: Container(
              color: Colors.black.withOpacity(0.2),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: logs.isEmpty
                  ? _buildEmptyLogsState()
                  : ListView.builder(
                      controller: _scrollController,
                      itemCount: logs.length,
                      itemBuilder: (context, index) {
                        final log = logs[index];
                        final catColor = _getCategoryColor(log.category);

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                          child: RichText(
                            text: TextSpan(
                              style: const TextStyle(
                                fontFamily: "monospace",
                                fontSize: 11.5,
                                height: 1.4,
                              ),
                              children: [
                                // Time
                                TextSpan(
                                  text: "${log.timeString} ",
                                  style: const TextStyle(color: AppColors.textMuted),
                                ),
                                // Category Tag
                                TextSpan(
                                  text: "[${log.category.name.toUpperCase().padRight(7)}] ",
                                  style: TextStyle(color: catColor, fontWeight: FontWeight.bold),
                                ),
                                // Message
                                TextSpan(
                                  text: log.message,
                                  style: const TextStyle(color: AppColors.textPrimary),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyLogsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.terminal, size: 32, color: AppColors.textMuted.withValues(alpha: 0.3)),
          const SizedBox(height: 12),
          const Text(
            "System console ready",
            style: TextStyle(
              fontFamily: "monospace",
              color: AppColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Text(
            "Events will be logged here in real-time",
            style: TextStyle(
              fontFamily: "monospace",
              color: AppColors.textMuted,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}
