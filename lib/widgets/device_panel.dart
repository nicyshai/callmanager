import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme.dart';
import '../models/call_model.dart';
import '../services/call_controller.dart';
import '../services/signaling_service.dart';

class DevicePanel extends ConsumerWidget {
  const DevicePanel({super.key});

  Widget _buildStatusBadge(SocketConnectionState connState) {
    Color badgeColor;
    String text;

    switch (connState) {
      case SocketConnectionState.connected:
        badgeColor = AppColors.success;
        text = "ONLINE";
        break;
      case SocketConnectionState.connecting:
        badgeColor = AppColors.warning;
        text = "CONNECTING";
        break;
      case SocketConnectionState.disconnected:
        badgeColor = AppColors.error;
        text = "OFFLINE";
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: badgeColor.withOpacity(0.3), width: 0.5),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: badgeColor,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controllerState = ref.watch(callControllerProvider);
    final localClient = ref.watch(localSignalingClientProvider);
    final connectionState = localClient.connectionState;
    final activeCall = controllerState.activeCall;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Search Bar Simulation
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search, color: AppColors.textMuted, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        "user_001 (This Device)",
                        style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                    _buildStatusBadge(connectionState),
                  ],
                ),
              ),
            ),

            // Content (Active Call, History or Loading)
            Expanded(
              child: ClipRRect(
                child: controllerState.isLoading
                    ? _buildLoadingState()
                    : (activeCall == null && controllerState.history.isEmpty
                        ? SingleChildScrollView(child: _buildEmptyState())
                        : Column(
                            children: [
                              if (activeCall != null)
                                _buildActiveCallCard(context, ref, activeCall),
                              Expanded(
                                child: ListView.builder(
                                  itemCount: controllerState.history.length,
                                  padding: EdgeInsets.zero,
                                  itemBuilder: (context, index) {
                                    return _buildHistoryItem(context, ref, controllerState.history[index]);
                                  },
                                ),
                              ),
                            ],
                          )),
              ),
            ),

            // Floating Dialer Button Simulation (at bottom of panel)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Align(
                alignment: Alignment.centerRight,
                child: FloatingActionButton(
                  onPressed: connectionState == SocketConnectionState.connected
                      ? () => ref.read(callControllerProvider.notifier).startCall('user_002')
                      : null,
                  backgroundColor: AppColors.primary,
                  elevation: 4,
                  child: const Icon(Icons.dialpad, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveCallCard(BuildContext context, WidgetRef ref, CallModel call) {
    final bool isOutgoing = call.callerId == 'user_001';
    
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.primary,
            child: const Icon(Icons.person, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isOutgoing ? "Calling user_002" : "Incoming call",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                Text(
                  call.state.name.toUpperCase(),
                  style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Row(
            children: [
              if (call.state == CallState.ringing && !isOutgoing)
                IconButton(
                  onPressed: () => ref.read(callControllerProvider.notifier).acceptCall(call.callId),
                  icon: const Icon(Icons.call, color: AppColors.success),
                  padding: EdgeInsets.zero,
                ),
              IconButton(
                onPressed: () {
                  if (call.state == CallState.ringing && isOutgoing) {
                    ref.read(callControllerProvider.notifier).cancelCall(call.callId);
                  } else {
                    ref.read(callControllerProvider.notifier).endCall(call.callId);
                  }
                },
                icon: const Icon(Icons.call_end, color: AppColors.error),
                padding: EdgeInsets.zero,
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildHistoryItem(BuildContext context, WidgetRef ref, CallModel item) {
    final isCaller = item.callerId == 'user_001';
    final targetId = isCaller ? item.receiverId : item.callerId;
    final isMissed = item.state == CallState.failed || item.state == CallState.rejected;
    
    return InkWell(
      onTap: () => ref.read(callControllerProvider.notifier).startCall(targetId),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.surfaceLight,
              child: Text(
                (isCaller ? item.receiverId : item.callerId).substring(0, 1).toUpperCase(),
                style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isCaller ? "To: ${item.receiverId}" : "From: ${item.callerId}",
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: isMissed && !isCaller ? AppColors.error : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        isCaller ? Icons.call_made : (isMissed ? Icons.call_missed : Icons.call_received),
                        size: 14,
                        color: isMissed ? AppColors.error : AppColors.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        "${item.state.name} • ${item.createdAt.hour}:${item.createdAt.minute.toString().padLeft(2, '0')}",
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.info_outline, color: AppColors.textMuted, size: 20),
            const SizedBox(width: 16),
            Icon(Icons.call, color: AppColors.primary, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight.withOpacity(0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.history, size: 48, color: AppColors.textMuted.withOpacity(0.5)),
          ),
          const SizedBox(height: 24),
          const Text(
            "No recent calls",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 8),
          const Text(
            "Your call history will appear here",
            style: TextStyle(color: AppColors.textMuted, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(strokeWidth: 3),
          const SizedBox(height: 16),
          Text(
            "Loading your calls...",
            style: TextStyle(color: AppColors.textMuted, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
