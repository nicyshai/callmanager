import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:callmanager/models/call_model.dart';
import 'package:callmanager/services/call_repository.dart';
import 'package:callmanager/services/callkit_service.dart';
import 'package:callmanager/services/signaling_service.dart';
import 'package:callmanager/services/call_controller.dart';

// Robust mock of SignalingClient with custom trigger methods
class MockSignalingClient extends SignalingClient {
  final List<Map<String, dynamic>> sentEvents = [];
  final _testController = StreamController<Map<String, dynamic>>.broadcast();

  MockSignalingClient() : super('user_001');

  @override
  Stream<Map<String, dynamic>> get onMessage => _testController.stream;

  @override
  SocketConnectionState get connectionState => SocketConnectionState.connected;

  @override
  Future<void> connect() async {}

  @override
  void disconnect() {}

  @override
  void sendEvent({
    required String to,
    required String event,
    required String callId,
    Map<String, dynamic>? extra,
  }) {
    sentEvents.add({
      'to': to,
      'event': event,
      'call_id': callId,
      if (extra != null) ...extra,
    });
  }

  void injectSocketMessage(Map<String, dynamic> data) {
    _testController.add(data);
  }

  void disposeTest() {
    _testController.close();
  }
}

// Robust mock of CallKitService
class MockCallKitService extends CallKitService {
  int showCallCount = 0;
  int endCallCount = 0;
  final _testController = StreamController<CallKitEvent>.broadcast();

  MockCallKitService() : super();

  @override
  Stream<CallKitEvent> get onEvent => _testController.stream;

  @override
  void _initNativeListener() {} // Disable native listener in tests

  @override
  Future<void> showIncomingCall(String callId, String callerName) async {
    showCallCount++;
  }

  @override
  Future<void> endActiveCall(String callId) async {
    endCallCount++;
    _testController.add(CallKitEvent(callId, CallKitAction.ended));
  }

  @override
  void simulateInAppAccept(String callId) {
    _testController.add(CallKitEvent(callId, CallKitAction.accept));
  }

  @override
  void simulateInAppDecline(String callId) {
    _testController.add(CallKitEvent(callId, CallKitAction.decline));
  }

  void disposeTest() {
    _testController.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Call Lifecycle State Machine Rules', () {
    test('State transitions follow specifications', () {
      // Ringing state transitions
      expect(CallState.ringing.canTransitionTo(CallState.accepting), isTrue);
      expect(CallState.ringing.canTransitionTo(CallState.cancelled), isTrue);
      expect(CallState.ringing.canTransitionTo(CallState.rejected), isTrue);
      expect(CallState.ringing.canTransitionTo(CallState.failed), isTrue);
      expect(CallState.ringing.canTransitionTo(CallState.ended), isTrue);

      // Connected state transitions
      expect(CallState.connected.canTransitionTo(CallState.ending), isTrue);
      expect(CallState.connected.canTransitionTo(CallState.ended), isTrue);
      expect(CallState.connected.canTransitionTo(CallState.failed), isTrue);

      // Terminal states are strict blockades
      for (final state in CallState.values) {
        if (state.isTerminal) {
          expect(state.canTransitionTo(CallState.connected), isFalse);
          expect(state.canTransitionTo(CallState.ringing), isFalse);
          expect(state.canTransitionTo(CallState.accepting), isFalse);
        }
      }
    });
  });

  group('CallRepository State Operations', () {
    late CallRepository repository;

    setUp(() {
      repository = InMemoryCallRepository();
    });

    test('Duplicate createCall retains first record and blocks duplicate entries', () async {
      final callId = 'call_123';
      final call1 = CallModel(
        callId: callId,
        callerId: 'user_002',
        receiverId: 'user_001',
        state: CallState.ringing,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final inserted1 = await repository.createCall(call1);
      expect(inserted1.state, CallState.ringing);

      final call2 = CallModel(
        callId: callId,
        callerId: 'user_002',
        receiverId: 'user_001',
        state: CallState.ringing,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final inserted2 = await repository.createCall(call2);
      
      // Verification: returned record is first record, size of database remains 1
      expect(inserted2, inserted1);
      final history = await repository.getCallHistory();
      expect(history.length, 1);
    });

    test('Invalid transitions throw InvalidStateTransitionException', () async {
      final callId = 'call_456';
      final call = CallModel(
        callId: callId,
        callerId: 'user_002',
        receiverId: 'user_001',
        state: CallState.ringing,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await repository.createCall(call);

      // Ringing -> Cancelled (terminal)
      await repository.updateCallState(callId, CallState.cancelled);

      // Transitioning terminal -> connecting must throw
      expect(
        () => repository.updateCallState(callId, CallState.connected),
        throwsA(isA<InvalidStateTransitionException>()),
      );
    });

    test('SQLite Recovery resets non-terminal calls to FAILED on restart', () async {
      final call1 = CallModel(
        callId: 'call_active',
        callerId: 'user_001',
        receiverId: 'user_002',
        state: CallState.connected,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final call2 = CallModel(
        callId: 'call_terminal',
        callerId: 'user_001',
        receiverId: 'user_002',
        state: CallState.ended,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await repository.createCall(call1);
      await repository.createCall(call2);

      await repository.recoverActiveCalls();

      final recovered1 = await repository.getCall('call_active');
      final recovered2 = await repository.getCall('call_terminal');

      // Verify active call transitioned to failed, terminal call remained untouched
      expect(recovered1?.state, CallState.failed);
      expect(recovered2?.state, CallState.ended);
    });
  });

  group('CallController Integration Logic', () {
    late InMemoryCallRepository repository;
    late MockSignalingClient signalingClient;
    late MockCallKitService callKitService;
    late CallController controller;

    setUp(() async {
      repository = InMemoryCallRepository();
      signalingClient = MockSignalingClient();
      callKitService = MockCallKitService();

      controller = CallController(
        repository: repository,
        signalingClient: signalingClient,
        callKitService: callKitService,
      );

      await controller.init();
    });

    tearDown(() {
      signalingClient.disposeTest();
    });

    test('Duplicate incoming call events trigger CallKit and database insertions exactly once', () async {
      final callId = 'call_dup_test';
      final incomingPayload = {
        'event': 'incoming_call',
        'call_id': callId,
        'caller_id': 'user_002',
        'receiver_id': 'user_001',
      };

      // Emit first event
      signalingClient.injectSocketMessage(incomingPayload);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(controller.state.activeCall?.callId, callId);
      expect(controller.state.activeCall?.state, CallState.ringing);
      expect(callKitService.showCallCount, 1);

      // Emit duplicate event
      signalingClient.injectSocketMessage(incomingPayload);
      await Future.delayed(const Duration(milliseconds: 50));

      // Assertions: call record still exists, CallKit count remains 1, state is unaffected
      expect(controller.state.activeCall?.state, CallState.ringing);
      expect(callKitService.showCallCount, 1);
      final history = await repository.getCallHistory();
      expect(history.length, 1);
    });

    test('Remote cancel during ringing transitions state to CANCELLED and fails accept safely', () async {
      final callId = 'call_cancel_race';
      
      // 1. Create call in ringing state
      signalingClient.injectSocketMessage({
        'event': 'incoming_call',
        'call_id': callId,
        'caller_id': 'user_002',
        'receiver_id': 'user_001',
      });
      await Future.delayed(const Duration(milliseconds: 50));

      expect(controller.state.activeCall?.state, CallState.ringing);

      // 2. Remote cancels call
      signalingClient.injectSocketMessage({
        'event': 'cancel_call',
        'call_id': callId,
      });
      await Future.delayed(const Duration(milliseconds: 50));

      // DB and activeCall state must be CANCELLED, CallKit dismissed
      final dbCall = await repository.getCall(callId);
      expect(dbCall?.state, CallState.cancelled);
      expect(controller.state.activeCall, isNull);
      expect(callKitService.endCallCount, 1);

      // 3. User attempts to Accept the cancelled call (simulates click race)
      // CallController exposes handlers, let's call accept on the controller
      // It should catch the error and log/terminate safely
      await controller.init(); // ensure clean state
      
      // Directly call local accept handler to trigger state machine check
      // Since it's private in call_controller, we simulate the CallKit action trigger:
      callKitService.simulateInAppAccept(callId);
      await Future.delayed(const Duration(milliseconds: 50));

      // DB call must remain in cancelled state
      final dbCallAfterAccept = await repository.getCall(callId);
      expect(dbCallAfterAccept?.state, CallState.cancelled);
    });

    test('Termination is idempotent and does not result in end-loops', () async {
      final callId = 'call_end_loop_test';

      // 1. Setup call via normal incoming flow
      signalingClient.injectSocketMessage({
        'event': 'incoming_call',
        'call_id': callId,
        'caller_id': 'user_002',
        'receiver_id': 'user_001',
      });
      await Future.delayed(const Duration(milliseconds: 50));
      expect(controller.state.activeCall?.state, CallState.ringing);
      
      // Answer
      callKitService.simulateInAppAccept(callId);
      // Wait for negotiation delay (1500ms) to connect
      await Future.delayed(const Duration(milliseconds: 1600));
      expect(controller.state.activeCall?.state, CallState.connected);

      // Clear event log count
      signalingClient.sentEvents.clear();

      // 2. Local User hangs up (triggers end call)
      await callKitService.endActiveCall(callId);
      
      // Wait long enough for both DB transitions (ENDING and ENDED)
      await Future.delayed(const Duration(seconds: 1));

      expect(controller.state.activeCall, isNull);
      final finalDbState = await repository.getCall(callId);
      expect(finalDbState?.state, CallState.ended);

      // Verify socket sent end_call EXACTLY once
      final endCallSocketEvents = signalingClient.sentEvents.where((e) => e['event'] == 'end_call').toList();
      expect(endCallSocketEvents.length, 1);

      // Clear mock queue
      signalingClient.sentEvents.clear();

      // 3. Simultaneously, remote user sends 'end_call' (arrives on socket)
      signalingClient.injectSocketMessage({
        'event': 'end_call',
        'call_id': callId,
      });
      await Future.delayed(const Duration(milliseconds: 50));

      // Assertions: State remains ENDED, no additional socket message is sent (no endless loop)
      final postRemoteEndState = await repository.getCall(callId);
      expect(postRemoteEndState?.state, CallState.ended);
      expect(signalingClient.sentEvents.isEmpty, isTrue);
    });
  });
}

extension on MockCallKitService {
  void simulateInAppEnd(String callId) {
    // Mimics the event stream injection of ending call
    // In our CallKitService, local hangup triggers CallKitAction.ended
    // We simulate this event coming from CallKit listener:
    // (We add it to the broadcast stream)
    simulateInAppEndEvent(callId);
  }

  void simulateInAppEndEvent(String callId) {
    try {
      // In CallKitService, _eventController is broadcast and exposes onEvent.
      // We can use the mock stream to send the event!
      // In the mock service, we override the stream or we can just access it.
      // In our code: _eventController.add(CallKitEvent(callId, CallKitAction.ended))
      // Since it's private in parent, we can just call it through public simulation methods
      // or write one. In our CallKitService, we have:
      // Future<void> endActiveCall(String callId) which adds event to _eventController
      endActiveCall(callId);
    } catch (_) {}
  }
}
