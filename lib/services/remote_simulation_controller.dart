import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:uuid/uuid.dart';
import '../core/logger.dart';
import '../models/call_model.dart';
import 'signaling_service.dart';

class RemoteSimulationState {
  final SocketConnectionState connectionState;
  final String? activeCallId;
  final CallState? callState;
  final String? callerId;
  final String? lastIncomingCallerId;

  RemoteSimulationState({
    required this.connectionState,
    this.activeCallId,
    this.callState,
    this.callerId,
    this.lastIncomingCallerId,
  });

  RemoteSimulationState.initial()
      : connectionState = SocketConnectionState.disconnected,
        activeCallId = null,
        callState = null,
        callerId = null,
        lastIncomingCallerId = null;

  RemoteSimulationState copyWith({
    SocketConnectionState? connectionState,
    String? activeCallId,
    bool clearActiveCall = false,
    CallState? callState,
    bool clearCallState = false,
    String? callerId,
    bool clearCallerId = false,
    String? lastIncomingCallerId,
    bool clearLastIncoming = false,
  }) {
    return RemoteSimulationState(
      connectionState: connectionState ?? this.connectionState,
      activeCallId: clearActiveCall ? null : (activeCallId ?? this.activeCallId),
      callState: clearCallState ? null : (callState ?? this.callState),
      callerId: clearCallerId ? null : (callerId ?? this.callerId),
      lastIncomingCallerId: clearLastIncoming ? null : (lastIncomingCallerId ?? this.lastIncomingCallerId),
    );
  }
}

class RemoteSimulationController extends StateNotifier<RemoteSimulationState> {
  final SignalingClient _remoteClient;
  StreamSubscription? _socketSubscription;
  StreamSubscription? _statusSubscription;
  bool _autoConnectInitialized = false;

  RemoteSimulationController(this._remoteClient)
      : super(RemoteSimulationState.initial()) {
    _socketSubscription = _remoteClient.onMessage.listen(_handleSocketMessage);
    _statusSubscription = _remoteClient.onConnectionStateChanged.listen(_handleConnectionState);
  }

  void initAutoConnect() {
    if (_autoConnectInitialized) return;
    _autoConnectInitialized = true;
    _remoteClient.connect();
  }

  void _handleConnectionState(SocketConnectionState stateVal) {
    state = state.copyWith(connectionState: stateVal);
  }

  void _handleSocketMessage(Map<String, dynamic> data) {
    final event = data['event'] as String?;
    final callId = data['call_id'] as String?;
    if (event == null || callId == null) return;

    AppLogger.system("[Remote User 002] Received socket event: '$event' for call: $callId");

    switch (event) {
      case 'incoming_call':
        state = state.copyWith(
          activeCallId: callId,
          callState: CallState.ringing,
          callerId: data['caller_id'] as String?,
          lastIncomingCallerId: data['caller_id'] as String?,
        );
        break;
      case 'accept_call':
        _handleRemoteAccept(callId);
        break;
      case 'cancel_call':
      case 'reject_call':
      case 'end_call':
        state = state.copyWith(
          clearActiveCall: true,
          clearCallState: true,
          clearCallerId: true,
        );
        break;
    }
  }

  Future<void> _handleRemoteAccept(String callId) async {
    state = state.copyWith(callState: CallState.accepting);
    await Future.delayed(const Duration(milliseconds: 1500));
    if (state.activeCallId == callId && state.callState == CallState.accepting) {
      state = state.copyWith(callState: CallState.connected);
      AppLogger.system("[Remote User 002] Call connected successfully");
    }
  }

  // --- Remote Simulator Trigger Methods ---

  /// Trigger an incoming call to user_001
  void triggerIncomingCall(String callId) {
    AppLogger.system("[Remote Simulation] Triggering Call to local user_001. ID: $callId");
    state = state.copyWith(
      activeCallId: callId,
      callState: CallState.ringing,
      callerId: 'user_002',
    );
    _remoteClient.sendEvent(
      to: 'user_001',
      event: 'incoming_call',
      callId: callId,
      extra: {
        'caller_id': 'user_002',
        'receiver_id': 'user_001',
      },
    );
  }

  /// Trigger accept of call sent by user_001
  Future<void> triggerAccept() async {
    final callId = state.activeCallId;
    if (callId == null) return;

    AppLogger.system("[Remote Simulation] Accepting incoming call from user_001...");
    state = state.copyWith(callState: CallState.accepting);
    
    _remoteClient.sendEvent(
      to: 'user_001',
      event: 'accept_call',
      callId: callId,
    );

    // Simulate establishing connection handshake
    await Future.delayed(const Duration(milliseconds: 1500));
    if (state.activeCallId == callId && state.callState == CallState.accepting) {
      state = state.copyWith(callState: CallState.connected);
      AppLogger.system("[Remote User 002] Call connected successfully");
    }
  }

  /// Trigger decline of call sent by user_001
  void triggerDecline() {
    final callId = state.activeCallId;
    if (callId == null) return;

    AppLogger.system("[Remote Simulation] Rejecting incoming call from user_001");
    _remoteClient.sendEvent(
      to: 'user_001',
      event: 'reject_call',
      callId: callId,
    );
    state = state.copyWith(
      clearActiveCall: true,
      clearCallState: true,
      clearCallerId: true,
    );
  }

  /// Trigger cancel of outgoing call before user_001 answers
  void triggerCancel() {
    final callId = state.activeCallId;
    if (callId == null) return;

    AppLogger.system("[Remote Simulation] Cancelling outgoing call: $callId");
    _remoteClient.sendEvent(
      to: 'user_001',
      event: 'cancel_call',
      callId: callId,
    );
    state = state.copyWith(
      clearActiveCall: true,
      clearCallState: true,
      clearCallerId: true,
    );
  }

  /// Trigger end of active call
  void triggerEnd() {
    final callId = state.activeCallId;
    if (callId == null) return;

    AppLogger.system("[Remote Simulation] Hanging up call: $callId");
    _remoteClient.sendEvent(
      to: 'user_001',
      event: 'end_call',
      callId: callId,
    );
    state = state.copyWith(
      clearActiveCall: true,
      clearCallState: true,
      clearCallerId: true,
    );
  }

  /// Trigger a call back to the last person who called this simulated user
  void triggerCallBack() {
    final targetId = state.lastIncomingCallerId;
    if (targetId == null) return;
    
    final callId = 'call_callback_${const Uuid().v4()}';
    AppLogger.system("[Remote Simulation] Calling back $targetId. ID: $callId");
    
    state = state.copyWith(
      activeCallId: callId,
      callState: CallState.ringing,
      callerId: 'user_002',
    );

    _remoteClient.sendEvent(
      to: targetId,
      event: 'incoming_call',
      callId: callId,
      extra: {
        'caller_id': 'user_002',
        'receiver_id': targetId,
      },
    );
  }

  // --- Network/Socket Interruption Emulation ---

  void toggleSocket() {
    if (state.connectionState == SocketConnectionState.connected) {
      AppLogger.system("[Remote Simulation] Intentionally disconnecting remote user_002 socket");
      _remoteClient.disconnect();
    } else {
      AppLogger.system("[Remote Simulation] Reconnecting remote user_002 socket");
      _remoteClient.connect();
    }
  }

  // --- Edge Case Simulation Actions ---

  /// Simulates duplicate incoming call triggers in rapid succession
  void simulateDuplicateIncoming(String callId) {
    AppLogger.system("[Remote Simulation] Injecting DUPLICATE incoming_call events...");
    // First event
    triggerIncomingCall(callId);
    
    // Duplicate event after a short delay
    Future.delayed(const Duration(milliseconds: 100), () {
      AppLogger.system("[Remote Simulation] Injecting second incoming_call event for same ID: $callId");
      _remoteClient.sendEvent(
        to: 'user_001',
        event: 'incoming_call',
        callId: callId,
        extra: {
          'caller_id': 'user_002',
          'receiver_id': 'user_001',
        },
      );
    });
  }

  /// Simulates out-of-order events: an end call received before the call record is created or accepted
  void simulateOutOfOrderEvents(String callId) {
    AppLogger.system("[Remote Simulation] Injecting out-of-order packet sequence (END before INCOMING)...");
    
    // Send END event first
    AppLogger.system("[Remote Simulation] Sending 'end_call' for unknown ID: $callId");
    _remoteClient.sendEvent(
      to: 'user_001',
      event: 'end_call',
      callId: callId,
    );

    // Send INCOMING event after 300ms
    Future.delayed(const Duration(milliseconds: 300), () {
      AppLogger.system("[Remote Simulation] Sending 'incoming_call' for call ID: $callId");
      triggerIncomingCall(callId);
    });
  }

  @override
  void dispose() {
    _socketSubscription?.cancel();
    _statusSubscription?.cancel();
    super.dispose();
  }
}

final remoteSimulationControllerProvider =
    StateNotifierProvider<RemoteSimulationController, RemoteSimulationState>((ref) {
  final remoteClient = ref.watch(remoteSignalingClientProvider);
  final controller = RemoteSimulationController(remoteClient);
  
  return controller;
});
