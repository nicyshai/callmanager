import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:uuid/uuid.dart';
import '../core/logger.dart';
import '../models/call_model.dart';
import 'call_repository.dart';
import 'callkit_service.dart';
import 'signaling_service.dart';

class CallControllerState {
  final CallModel? activeCall;
  final List<CallModel> history;
  final String? errorMessage;
  final bool isLoading;

  CallControllerState({
    this.activeCall,
    required this.history,
    this.errorMessage,
    this.isLoading = false,
  });

  CallControllerState.initial()
      : activeCall = null,
        history = [],
        errorMessage = null,
        isLoading = false;

  CallControllerState copyWith({
    CallModel? activeCall,
    bool clearActiveCall = false,
    List<CallModel>? history,
    String? errorMessage,
    bool clearErrorMessage = false,
    bool? isLoading,
  }) {
    return CallControllerState(
      activeCall: clearActiveCall ? null : (activeCall ?? this.activeCall),
      history: history ?? this.history,
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class CallController extends StateNotifier<CallControllerState> with WidgetsBindingObserver {
  final CallRepository _repository;
  final SignalingClient _signalingClient;
  final CallKitService _callKitService;

  StreamSubscription? _socketSubscription;
  StreamSubscription? _callKitSubscription;
  bool _initialized = false;

  CallController({
    required CallRepository repository,
    required SignalingClient signalingClient,
    required CallKitService callKitService,
  })  : _repository = repository,
        _signalingClient = signalingClient,
        _callKitService = callKitService,
        super(CallControllerState.initial()) {
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> init({bool force = false}) async {
    if (_initialized && !force) return;
    _initialized = true;

    state = state.copyWith(isLoading: true);
    AppLogger.system(force ? "Forcing CallController restart..." : "Initializing CallController...");

    try {
      // Initialize repository
      await _repository.init();

      // Recover any active calls from a crashed/terminated state
      await _repository.recoverActiveCalls();

      // Load call history
      final history = await _repository.getCallHistory();
      state = state.copyWith(history: history, isLoading: false);

      if (!force) {
        // Listen to socket client events
        _socketSubscription = _signalingClient.onMessage.listen(_handleSocketMessage);

        // Listen to CallKit actions
        _callKitSubscription = _callKitService.onEvent.listen(_handleCallKitEvent);
      }

      AppLogger.system("CallController ${force ? 'restarted' : 'initialized'} successfully");
    } catch (e) {
      AppLogger.error("Failed to ${force ? 'restart' : 'initialize'} CallController: $e");
      state = state.copyWith(isLoading: false, errorMessage: "Database Initialization Failed");
    }
  }

  // --- WebSocket Message Handler ---
  Future<void> _handleSocketMessage(Map<String, dynamic> data) async {
    final event = data['event'] as String?;
    final callId = data['call_id'] as String?;
    if (event == null || callId == null || callId.isEmpty) {
      AppLogger.error("Received malformed socket message: $data");
      return;
    }

    switch (event) {
      case 'incoming_call':
        await _handleRemoteIncomingCall(data);
        break;
      case 'accept_call':
        await _handleRemoteAccept(callId);
        break;
      case 'reject_call':
        await _handleRemoteReject(callId);
        break;
      case 'cancel_call':
        await _handleRemoteCancel(callId);
        break;
      case 'end_call':
        await _handleRemoteEnd(callId);
        break;
      case 'error':
        final msg = data['message'] as String? ?? 'Socket Error';
        AppLogger.error("Signaling Error message received: $msg");
        state = state.copyWith(errorMessage: msg);
        break;
    }
  }

  // --- CallKit Event Handler ---
  Future<void> _handleCallKitEvent(CallKitEvent event) async {
    AppLogger.state("Controller received CallKit action: ${event.action.name} for ${event.callId}");
    switch (event.action) {
      case CallKitAction.accept:
        await _handleLocalAccept(event.callId);
        break;
      case CallKitAction.decline:
        await _handleLocalDecline(event.callId);
        break;
      case CallKitAction.ended:
        await _handleLocalEnd(event.callId);
        break;
      case CallKitAction.timeout:
        await _handleLocalTimeout(event.callId);
        break;
    }
  }

  // --- Incoming Call (Remote caller initiates call to this device) ---
  Future<void> _handleRemoteIncomingCall(Map<String, dynamic> data) async {
    final callId = data['call_id'] as String;
    final callerId = data['caller_id'] as String? ?? 'user_002';
    final receiverId = data['receiver_id'] as String? ?? 'user_001';

    AppLogger.state("Processing incoming call: $callId from $callerId");

    try {
      // 1. Transactional check & save to DB
      final existingCall = await _repository.getCall(callId);
      if (existingCall != null) {
        if (existingCall.state == CallState.ringing) {
          AppLogger.state("Duplicate incoming_call event for call $callId ignored (idempotent)");
          return;
        }
        AppLogger.state("Incoming call $callId already in state: ${existingCall.state.name}. Ignoring out-of-order incoming call.");
        return;
      }

      final newCall = CallModel(
        callId: callId,
        callerId: callerId,
        receiverId: receiverId,
        state: CallState.ringing,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final savedCall = await _repository.createCall(newCall);
      AppLogger.state("Call record saved to DB: ${savedCall.callId}");
      state = state.copyWith(activeCall: savedCall, history: await _repository.getCallHistory());
      AppLogger.state("Controller history updated. Count: ${state.history.length}");

      // 2. Trigger CallKit incoming prompt
      await _callKitService.showIncomingCall(callId, callerId);
    } catch (e) {
      AppLogger.error("Failed to process incoming call event: $e");
    }
  }

  // --- Local Accept (This device user answers call) ---
  Future<void> _handleLocalAccept(String callId) async {
    AppLogger.state("Processing local Accept for call $callId");
    try {
      // 1. Transition state: RINGING -> ACCEPTING
      final updatedCall = await _repository.updateCallState(callId, CallState.accepting);
      state = state.copyWith(activeCall: updatedCall, history: await _repository.getCallHistory());

      // 2. Notify remote caller via Socket
      _signalingClient.sendEvent(
        to: updatedCall.callerId,
        event: 'accept_call',
        callId: callId,
      );

      // 3. Simulate media/handshake delay
      AppLogger.system("Establishing secure connection handshake...");
      await Future.delayed(const Duration(milliseconds: 1500));

      // 4. Verify call state hasn't changed during handshake (e.g., cancelled remotely)
      final currentCall = await _repository.getCall(callId);
      if (currentCall == null || currentCall.state != CallState.accepting) {
        AppLogger.state("Call $callId state mutated during negotiation. Connection abort.");
        return;
      }

      // 5. Transition state: ACCEPTING -> CONNECTED
      final connectedCall = await _repository.updateCallState(callId, CallState.connected);
      state = state.copyWith(activeCall: connectedCall, history: await _repository.getCallHistory());
      AppLogger.state("Call $callId is now CONNECTED");
    } on InvalidStateTransitionException catch (e) {
      AppLogger.error("Local Accept aborted. State changed prior to connection: $e");
      await _callKitService.endActiveCall(callId);
      state = state.copyWith(
        clearActiveCall: true,
        errorMessage: "Call cancelled by caller",
        history: await _repository.getCallHistory(),
      );
    } catch (e) {
      AppLogger.error("Unexpected error in local accept: $e");
    }
  }

  // --- Remote Accept (Remote user answers our outgoing call) ---
  Future<void> _handleRemoteAccept(String callId) async {
    AppLogger.state("Processing remote Accept for call $callId");
    try {
      // Transition state: RINGING -> ACCEPTING
      final updatedCall = await _repository.updateCallState(callId, CallState.accepting);
      state = state.copyWith(activeCall: updatedCall, history: await _repository.getCallHistory());

      // Simulate handshake connection delay
      AppLogger.system("Negotiating connection with remote...");
      await Future.delayed(const Duration(milliseconds: 1500));

      // Validate call status
      final currentCall = await _repository.getCall(callId);
      if (currentCall == null || currentCall.state != CallState.accepting) {
        AppLogger.state("Call $callId state mutated during negotiation. Connection abort.");
        return;
      }

      // Transition state: ACCEPTING -> CONNECTED
      final connectedCall = await _repository.updateCallState(callId, CallState.connected);
      state = state.copyWith(activeCall: connectedCall, history: await _repository.getCallHistory());
      AppLogger.state("Call $callId is now CONNECTED");
    } on InvalidStateTransitionException catch (e) {
      AppLogger.error("Remote Accept rejected by state machine: $e");
    } catch (e) {
      AppLogger.error("Unexpected error in remote accept: $e");
    }
  }

  // --- Local Decline (This device user rejects incoming call) ---
  Future<void> _handleLocalDecline(String callId) async {
    AppLogger.state("Processing local Decline for call $callId");
    try {
      final updatedCall = await _repository.updateCallState(callId, CallState.rejected);
      state = state.copyWith(clearActiveCall: true, history: await _repository.getCallHistory());

      // Notify remote caller
      _signalingClient.sendEvent(
        to: updatedCall.callerId,
        event: 'reject_call',
        callId: callId,
      );
    } on InvalidStateTransitionException catch (e) {
      AppLogger.state("Local Decline ignored: $e");
    } catch (e) {
      AppLogger.error("Error in local decline: $e");
    }
  }

  // --- Remote Reject (Remote user declines our outgoing call) ---
  Future<void> _handleRemoteReject(String callId) async {
    AppLogger.state("Processing remote Reject for call $callId");
    try {
      await _repository.updateCallState(callId, CallState.rejected);

      if (state.activeCall?.callId == callId) {
        state = state.copyWith(clearActiveCall: true, history: await _repository.getCallHistory());
      } else {
        state = state.copyWith(history: await _repository.getCallHistory());
      }

      await _callKitService.endActiveCall(callId);
    } on InvalidStateTransitionException catch (e) {
      AppLogger.state("Remote Reject ignored: $e");
    } catch (e) {
      AppLogger.error("Error in remote reject: $e");
    }
  }

  // --- Remote Cancel (Remote caller cancels before we accept) ---
  Future<void> _handleRemoteCancel(String callId) async {
    AppLogger.state("Processing remote Cancel for call $callId");
    try {
      await _repository.updateCallState(callId, CallState.cancelled);

      if (state.activeCall?.callId == callId) {
        state = state.copyWith(clearActiveCall: true, history: await _repository.getCallHistory());
      } else {
        state = state.copyWith(history: await _repository.getCallHistory());
      }

      // Dismiss CallKit
      await _callKitService.endActiveCall(callId);
    } on InvalidStateTransitionException catch (e) {
      AppLogger.state("Remote Cancel ignored (idempotent): $e");
    } catch (e) {
      AppLogger.error("Error in remote cancel: $e");
    }
  }

  // --- Local Timeout (Call rings too long without action) ---
  Future<void> _handleLocalTimeout(String callId) async {
    AppLogger.state("Processing local Timeout for call $callId");
    try {
      await _repository.updateCallState(callId, CallState.failed);

      if (state.activeCall?.callId == callId) {
        state = state.copyWith(clearActiveCall: true, history: await _repository.getCallHistory());
      } else {
        state = state.copyWith(history: await _repository.getCallHistory());
      }
    } on InvalidStateTransitionException catch (e) {
      AppLogger.state("Local Timeout ignored: $e");
    } catch (e) {
      AppLogger.error("Error in local timeout: $e");
    }
  }

  // --- Local End (This device user hangs up call) ---
  Future<void> _handleLocalEnd(String callId) async {
    AppLogger.state("Processing local End for call $callId");
    try {
      final currentCall = await _repository.getCall(callId);
      if (currentCall == null) return;

      // 1. Transition state: CONNECTED -> ENDING
      final endingCall = await _repository.updateCallState(callId, CallState.ending);
      state = state.copyWith(activeCall: endingCall, history: await _repository.getCallHistory());

      // 2. Notify remote user via Socket
      final destinationId = currentCall.callerId == _signalingClient.userId
          ? currentCall.receiverId
          : currentCall.callerId;

      _signalingClient.sendEvent(
        to: destinationId,
        event: 'end_call',
        callId: callId,
      );

      // 3. Transition state: ENDING -> ENDED (Terminal)
      final endedCall = await _repository.updateCallState(callId, CallState.ended);
      AppLogger.state("Call terminal state updated in DB: ${endedCall.state.name}");
      state = state.copyWith(clearActiveCall: true, history: await _repository.getCallHistory());
      AppLogger.state("Controller history updated after end. Count: ${state.history.length}");

      // 4. Dismiss CallKit
      await _callKitService.endActiveCall(callId);
    } on InvalidStateTransitionException catch (e) {
      AppLogger.state("Local End ignored (already ended): $e");
    } catch (e) {
      AppLogger.error("Error in local end: $e");
    }
  }

  // --- Remote End (Remote user hangs up call) ---
  Future<void> _handleRemoteEnd(String callId) async {
    AppLogger.state("Processing remote End for call $callId");
    try {
      // Transition state directly to ENDED
      await _repository.updateCallState(callId, CallState.ended);

      if (state.activeCall?.callId == callId) {
        state = state.copyWith(clearActiveCall: true, history: await _repository.getCallHistory());
      } else {
        state = state.copyWith(history: await _repository.getCallHistory());
      }

      // Dismiss CallKit
      await _callKitService.endActiveCall(callId);
    } on InvalidStateTransitionException catch (e) {
      AppLogger.state("Remote End event ignored (idempotent): $e");
    } catch (e) {
      AppLogger.error("Error in remote end: $e");
    }
  }

  // --- Local User triggers Outgoing Call to remote ---
  Future<void> startCall(String receiverId) async {
    if (state.activeCall != null) {
      AppLogger.error("Start call blocked: another call is active");
      return;
    }

    final callId = 'call_${const Uuid().v4()}';
    AppLogger.state("Initiating outgoing call: $callId to $receiverId");

    try {
      final newCall = CallModel(
        callId: callId,
        callerId: _signalingClient.userId,
        receiverId: receiverId,
        state: CallState.ringing,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final savedCall = await _repository.createCall(newCall);
      AppLogger.state("Call record saved to DB: ${savedCall.callId}");
      state = state.copyWith(activeCall: savedCall, history: await _repository.getCallHistory());
      AppLogger.state("Controller history updated. Count: ${state.history.length}");

      // Emit incoming_call over socket to remote receiver
      _signalingClient.sendEvent(
        to: receiverId,
        event: 'incoming_call',
        callId: callId,
        extra: {
          'caller_id': _signalingClient.userId,
          'receiver_id': receiverId,
        },
      );
    } catch (e) {
      AppLogger.error("Failed to start call: $e");
    }
  }

  // --- Local User cancels Outgoing Call ---
  Future<void> cancelCall(String callId) async {
    AppLogger.state("Processing local Cancel for outgoing call $callId");
    try {
      final updatedCall = await _repository.updateCallState(callId, CallState.cancelled);
      state = state.copyWith(clearActiveCall: true, history: await _repository.getCallHistory());

      // Notify remote receiver
      _signalingClient.sendEvent(
        to: updatedCall.receiverId,
        event: 'cancel_call',
        callId: callId,
      );
    } on InvalidStateTransitionException catch (e) {
      AppLogger.state("Local cancel outgoing call ignored: $e");
    } catch (e) {
      AppLogger.error("Error in local cancel: $e");
    }
  }

  // --- Public UI Actions ---
  // These expose the local accept/decline/end handlers to callers outside this
  // file (e.g. DevicePanel), since the underlying handlers are also invoked
  // internally from native CallKit events and stay private.
  Future<void> acceptCall(String callId) => _handleLocalAccept(callId);

  Future<void> declineCall(String callId) => _handleLocalDecline(callId);

  Future<void> endCall(String callId) => _handleLocalEnd(callId);

  // --- Clear History ---
  Future<void> clearHistory() async {
    await _repository.clearAll();
    state = state.copyWith(clearActiveCall: true, history: []);
    _callKitService.dismissSimulation();
  }

  // --- Error Handling Clean ---
  void clearError() {
    state = state.copyWith(clearErrorMessage: true);
  }

  // --- App Lifecycle Observer Hooks ---
  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    AppLogger.system("App Lifecycle State changed: ${lifecycleState.name}");
    if (lifecycleState == AppLifecycleState.resumed) {
      _handleAppResume();
    } else if (lifecycleState == AppLifecycleState.paused) {
      _handleAppPause();
    }
  }

  Future<void> _handleAppResume() async {
    AppLogger.system("App resumed. Resyncing state and socket...");

    // Connect socket if it was disconnected
    if (_signalingClient.connectionState == SocketConnectionState.disconnected) {
      _signalingClient.connect();
    }

    // Recover database call states (ensure we don't have dangling active states)
    final active = state.activeCall;
    if (active != null) {
      final dbState = await _repository.getCall(active.callId);
      if (dbState != null && dbState.state != active.state) {
        AppLogger.system("Syncing UI call state to match DB state: ${dbState.state.name}");
        if (dbState.state.isTerminal) {
          state = state.copyWith(clearActiveCall: true, history: await _repository.getCallHistory());
          await _callKitService.endActiveCall(active.callId);
        } else {
          state = state.copyWith(activeCall: dbState, history: await _repository.getCallHistory());
        }
      }
    }
  }

  void _handleAppPause() {
    AppLogger.system("App moved to background/paused.");
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _socketSubscription?.cancel();
    _callKitSubscription?.cancel();
    super.dispose();
  }
}

/// Riverpod provider for the [CallController] StateNotifier
final callControllerProvider =
StateNotifierProvider<CallController, CallControllerState>((ref) {
  final repository = ref.watch(callRepositoryProvider);
  final signalingClient = ref.watch(localSignalingClientProvider);
  final callKitService = ref.watch(callKitServiceProvider);

  final controller = CallController(
    repository: repository,
    signalingClient: signalingClient,
    callKitService: callKitService,
  );

  return controller;
});