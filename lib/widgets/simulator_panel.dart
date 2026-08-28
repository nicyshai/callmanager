import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../core/theme.dart';
import '../models/call_model.dart';
import '../services/call_controller.dart';
import '../services/remote_simulation_controller.dart';
import '../services/signaling_service.dart';

class SimulatorPanel extends ConsumerWidget {
  const SimulatorPanel({super.key});

  Widget _buildStatusBadge(SocketConnectionState connState) {
    Color badgeColor;
    String text;
    IconData icon;

    switch (connState) {
      case SocketConnectionState.connected:
        badgeColor = AppColors.success;
        text = "ONLINE";
        icon = Icons.sensors;
        break;
      case SocketConnectionState.connecting:
        badgeColor = AppColors.warning;
        text = "CONNECTING";
        icon = Icons.sync;
        break;
      case SocketConnectionState.disconnected:
        badgeColor = AppColors.error;
        text = "OFFLINE";
        icon = Icons.sensors_off;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: badgeColor.withOpacity(0.4), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: badgeColor, size: 14),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: badgeColor,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallStateBadge(CallState stateVal) {
    Color badgeColor;
    switch (stateVal) {
      case CallState.ringing:
        badgeColor = AppColors.warning;
        break;
      case CallState.accepting:
        badgeColor = AppColors.info;
        break;
      case CallState.connected:
        badgeColor = AppColors.success;
        break;
      case CallState.ending:
        badgeColor = Colors.orange;
        break;
      default:
        badgeColor = AppColors.textMuted;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: badgeColor.withOpacity(0.5), width: 1),
      ),
      child: Text(
        stateVal.name.toUpperCase(),
        style: TextStyle(
          color: badgeColor,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final simState = ref.watch(remoteSimulationControllerProvider);
    final simNotifier = ref.read(remoteSimulationControllerProvider.notifier);

    final isOnline = simState.connectionState == SocketConnectionState.connected;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.glassBox(),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header / Connection Block
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "REMOTE SIMULATOR",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      "user_002 (Simulated)",
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    _buildStatusBadge(simState.connectionState),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(
                        isOnline ? Icons.power_off : Icons.power,
                        size: 20,
                      ),
                      tooltip: isOnline ? "Simulate Client Disconnection" : "Simulate Client Reconnection",
                      onPressed: () => simNotifier.toggleSocket(),
                    ),
                  ],
                ),
              ],
            ),
            
            const Divider(height: 24),
    
            // Active Call State Card / Trigger Actions
            simState.activeCallId == null
                ? _buildIdleTriggers(context, ref, simState, simNotifier, isOnline)
                : _buildActiveSimulatorCall(context, ref, simState, simNotifier),
          ],
        ),
      ),
    );
  }

  Widget _buildIdleTriggers(
    BuildContext context,
    WidgetRef ref,
    RemoteSimulationState simState,
    RemoteSimulationController simNotifier,
    bool isOnline,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Center(
          child: Column(
            children: [
              const Icon(Icons.settings_suggest, size: 36, color: AppColors.textMuted),
              const SizedBox(height: 8),
              const Text(
                "Remote Simulation Control",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              Text(
                isOnline
                    ? "Choose a simulation action below to broadcast network signaling events to user_001."
                    : "Remote client is offline. Connect remote client to trigger signaling events.",
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Action 1: Standard Ringing Call user_002 -> user_001
        ElevatedButton.icon(
          onPressed: isOnline
              ? () {
                  final callId = 'call_${const Uuid().v4()}';
                  simNotifier.triggerIncomingCall(callId);
                }
              : null,
          icon: const Icon(Icons.ring_volume, size: 16),
          label: const Text("Trigger Incoming Call (user_002 -> Local)"),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.surfaceLight,
            disabledForegroundColor: AppColors.textMuted,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
        if (simState.lastIncomingCallerId != null) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: isOnline ? () => simNotifier.triggerCallBack() : null,
            icon: const Icon(Icons.history, size: 16),
            label: Text("Call Back ${simState.lastIncomingCallerId}"),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ],
        const SizedBox(height: 12),

        const Text(
          "RELIABILITY EDGE-CASE TESTS",
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textMuted, letterSpacing: 0.5),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),

        // Grid of test triggers
        GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 2.2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            // Test Trigger A: Duplicate events
            _buildTestCard(
              title: "Duplicate Ringing",
              subtitle: "Double Incoming Call",
              icon: Icons.copy,
              onPressed: isOnline
                  ? () {
                      final callId = 'call_dup_${DateTime.now().millisecondsSinceEpoch}';
                      simNotifier.simulateDuplicateIncoming(callId);
                    }
                  : null,
            ),
            
            // Test Trigger B: Out-of-order
            _buildTestCard(
              title: "Out-Of-Order Event",
              subtitle: "Send End then Ringing",
              icon: Icons.alt_route,
              onPressed: isOnline
                  ? () {
                      final callId = 'call_ooo_${DateTime.now().millisecondsSinceEpoch}';
                      simNotifier.simulateOutOfOrderEvents(callId);
                    }
                  : null,
            ),

            // Test Trigger C: Remote cancel race condition
            _buildTestCard(
              title: "Remote Cancel",
              subtitle: "Cancel right after Ringing",
              icon: Icons.cancel_presentation,
              onPressed: isOnline
                  ? () {
                      final callId = 'call_race_${DateTime.now().millisecondsSinceEpoch}';
                      simNotifier.triggerIncomingCall(callId);
                      Future.delayed(const Duration(milliseconds: 600), () {
                        simNotifier.triggerCancel();
                      });
                    }
                  : null,
            ),

            // Test Trigger D: Network disconnect during Call
            _buildTestCard(
              title: "Simulate Restart",
              subtitle: "Crash local database state",
              icon: Icons.restart_alt,
              onPressed: () {
                // Re-initialize local controller to trigger SQLite recovery!
                ref.read(callControllerProvider.notifier).init(force: true);
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTestCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    final bool isEnabled = onPressed != null;

    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isEnabled ? AppColors.surfaceLight.withOpacity(0.4) : AppColors.surfaceLight.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isEnabled ? AppColors.border : AppColors.border.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isEnabled ? AppColors.info : AppColors.textMuted,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isEnabled ? AppColors.textPrimary : AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 9, color: AppColors.textMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveSimulatorCall(
    BuildContext context,
    WidgetRef ref,
    RemoteSimulationState state,
    RemoteSimulationController simNotifier,
  ) {
    final bool isOutgoing = state.callerId == 'user_002'; // call initiated by user_002

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Column(
            children: [
              if (state.callState != null) _buildCallStateBadge(state.callState!),
              const SizedBox(height: 12),
              Text(
                isOutgoing ? "Outgoing Call Ringing..." : "Ringing Incoming...",
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                "ID: ${state.activeCallId!.length > 25 ? '${state.activeCallId!.substring(0, 8)}...' : state.activeCallId}",
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontFamily: "monospace"),
              ),
            ],
          ),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Column(
                children: [
                  const Text("Caller", style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                  const SizedBox(height: 4),
                  Text(state.callerId ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
              Container(width: 1, height: 24, color: AppColors.border),
              Column(
                children: [
                  const Text("Receiver", style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                  const SizedBox(height: 4),
                  Text(isOutgoing ? 'user_001' : 'user_002', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
            ],
          ),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Case 1: user_002 is receiving a call from user_001 -> Decline / Accept
              if (state.callState == CallState.ringing && !isOutgoing) ...[
                IconButton.filled(
                  icon: const Icon(Icons.call_end),
                  style: IconButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: AppColors.error,
                  ),
                  iconSize: 22,
                  padding: const EdgeInsets.all(12),
                  onPressed: () => simNotifier.triggerDecline(),
                ),
                const SizedBox(width: 40),
                IconButton.filled(
                  icon: const Icon(Icons.phone),
                  style: IconButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: AppColors.success,
                  ),
                  iconSize: 22,
                  padding: const EdgeInsets.all(12),
                  onPressed: () => simNotifier.triggerAccept(),
                ),
              ],

              // Case 2: user_002 initiated the call, ringing -> Cancel
              if (state.callState == CallState.ringing && isOutgoing)
                ElevatedButton.icon(
                  onPressed: () => simNotifier.triggerCancel(),
                  icon: const Icon(Icons.close),
                  label: const Text("Cancel Call"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                  ),
                ),

              // Case 3: accepting / handshaking
              if (state.callState == CallState.accepting)
                const Column(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.info),
                    ),
                    SizedBox(height: 8),
                    Text("Handshaking...", style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),

              // Case 4: Connected -> End Call
              if (state.callState == CallState.connected)
                ElevatedButton.icon(
                  onPressed: () => simNotifier.triggerEnd(),
                  icon: const Icon(Icons.call_end),
                  label: const Text("Hang Up"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
