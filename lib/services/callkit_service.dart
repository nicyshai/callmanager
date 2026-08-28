import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateNotifier, StateNotifierProvider;
import '../core/logger.dart';

enum CallKitAction {
  accept,
  decline,
  ended,
  timeout,
}

class CallKitEvent {
  final String callId;
  final CallKitAction action;

  CallKitEvent(this.callId, this.action);

  @override
  String toString() => 'CallKitEvent(callId: $callId, action: ${action.name})';
}

/// State model for the simulated CallKit overlay
class CallKitOverlayState {
  final String callId;
  final String callerName;
  final bool isVisible;

  CallKitOverlayState({
    required this.callId,
    required this.callerName,
    this.isVisible = false,
  });

  CallKitOverlayState.empty()
      : callId = '',
        callerName = '',
        isVisible = false;
}

class CallKitOverlayNotifier extends StateNotifier<CallKitOverlayState> {
  CallKitOverlayNotifier() : super(CallKitOverlayState.empty());

  void show(String callId, String callerName) {
    state = CallKitOverlayState(callId: callId, callerName: callerName, isVisible: true);
  }

  void hide() {
    state = CallKitOverlayState.empty();
  }
}

final callKitOverlayProvider =
StateNotifierProvider<CallKitOverlayNotifier, CallKitOverlayState>((ref) {
  return CallKitOverlayNotifier();
});

class CallKitService {
  final Ref? _ref;
  final _eventController = StreamController<CallKitEvent>.broadcast();
  StreamSubscription? _nativeSubscription;

  CallKitService([this._ref]) {
    _initNativeListener();
  }

  Stream<CallKitEvent> get onEvent => _eventController.stream;

  bool get _isMobile {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  void _initNativeListener() {
    if (!_isMobile) return;

    try {
      _nativeSubscription = FlutterCallkitIncoming.onEvent.listen((CallEvent? event) {
        if (event == null) return;

        AppLogger.callkit("Native CallKit Event: ${event.eventName}");

        switch (event) {
          case CallEventActionCallAccept(:final callKitParams):
            if (callKitParams.id.isEmpty) return;
            _eventController.add(CallKitEvent(callKitParams.id, CallKitAction.accept));
          case CallEventActionCallDecline(:final callKitParams):
            if (callKitParams.id.isEmpty) return;
            _eventController.add(CallKitEvent(callKitParams.id, CallKitAction.decline));
          case CallEventActionCallEnded(:final callKitParams):
            if (callKitParams.id.isEmpty) return;
            _eventController.add(CallKitEvent(callKitParams.id, CallKitAction.ended));
          case CallEventActionCallTimeout(:final id):
            if (id.isEmpty) return;
            _eventController.add(CallKitEvent(id, CallKitAction.timeout));
          default:
          // Other events (push token updates, hold/mute/dtmf/etc.) ignored
            break;
        }
      }, onError: (err) {
        AppLogger.error("Native CallKit Stream Error: $err");
      });
    } catch (e) {
      AppLogger.error("Failed to initialize native CallKit listener: $e");
    }
  }

  Future<void> showIncomingCall(String callId, String callerName) async {
    AppLogger.callkit("Request to show incoming call prompt for $callId ($callerName)");

    if (!_isMobile) {
      // Trigger simulation overlay
      AppLogger.callkit("Non-mobile platform detected. Displaying in-app CallKit overlay simulator.");
      _ref?.read(callKitOverlayProvider.notifier).show(callId, callerName);
      return;
    }

    try {
      final params = CallKitParams(
        id: callId,
        nameCaller: callerName,
        appName: 'CallManager',
        avatar: 'https://i.pravatar.cc/100',
        handle: '00000000',
        type: 0, // Video: 0 (Audio), 1 (Video)
        duration: 30000,
        missedCallNotification: const NotificationParams(
          showNotification: true,
          subtitle: 'Missed Call',
          callbackText: 'Call Back',
        ),
        android: const AndroidParams(
          isShowLogo: true,
          incomingCallNotificationChannelName: 'Incoming Call',
          textAccept: 'Accept',
          textDecline: 'Decline',
        ),
        ios: const IOSParams(
          iconName: 'AppIcon',
          handleType: 'generic',
          supportsVideo: false,
          maximumCallGroups: 1,
          maximumCallsPerCallGroup: 1,
        ),
      );

      await FlutterCallkitIncoming.showCallkitIncoming(params);
      AppLogger.callkit("Native CallKit showCallkitIncoming triggered successfully");
    } catch (e) {
      AppLogger.error("Failed to show native CallKit: $e. Falling back to in-app overlay.");
      _ref?.read(callKitOverlayProvider.notifier).show(callId, callerName);
    }
  }

  Future<void> acceptIncomingCall(String callId) async {
    AppLogger.callkit("Local accepted call: $callId");

    // Hide overlay if visible
    _ref?.read(callKitOverlayProvider.notifier).hide();

    if (_isMobile) {
      try {
        await FlutterCallkitIncoming.startCall(CallKitParams(id: callId));
        AppLogger.callkit("Native CallKit startCall triggered");
      } catch (e) {
        AppLogger.error("Failed to start CallKit call natively: $e");
      }
    }

    // Broadcast event
    _eventController.add(CallKitEvent(callId, CallKitAction.accept));
  }

  Future<void> declineIncomingCall(String callId) async {
    AppLogger.callkit("Local declined call: $callId");

    // Hide overlay if visible
    _ref?.read(callKitOverlayProvider.notifier).hide();

    if (_isMobile) {
      try {
        await FlutterCallkitIncoming.endCall(callId);
        AppLogger.callkit("Native CallKit endCall (decline) triggered");
      } catch (e) {
        AppLogger.error("Failed to decline CallKit call natively: $e");
      }
    }

    // Broadcast event
    _eventController.add(CallKitEvent(callId, CallKitAction.decline));
  }

  Future<void> endActiveCall(String callId) async {
    AppLogger.callkit("Local ended call: $callId");

    // Hide overlay if visible
    _ref?.read(callKitOverlayProvider.notifier).hide();

    if (_isMobile) {
      try {
        await FlutterCallkitIncoming.endCall(callId);
        AppLogger.callkit("Native CallKit endCall triggered");
      } catch (e) {
        AppLogger.error("Failed to end CallKit call natively: $e");
      }
    }

    // Broadcast event
    _eventController.add(CallKitEvent(callId, CallKitAction.ended));
  }

  void simulateInAppAccept(String callId) {
    AppLogger.callkit("Simulated CallKit Accept clicked on overlay");
    _ref?.read(callKitOverlayProvider.notifier).hide();
    _eventController.add(CallKitEvent(callId, CallKitAction.accept));
  }

  void simulateInAppDecline(String callId) {
    AppLogger.callkit("Simulated CallKit Decline clicked on overlay");
    _ref?.read(callKitOverlayProvider.notifier).hide();
    _eventController.add(CallKitEvent(callId, CallKitAction.decline));
  }

  void dismissSimulation() {
    _ref?.read(callKitOverlayProvider.notifier).hide();
  }

  void dispose() {
    _nativeSubscription?.cancel();
    _eventController.close();
  }
}

final callKitServiceProvider = Provider<CallKitService>((ref) {
  final service = CallKitService(ref);
  ref.onDispose(() => service.dispose());
  return service;
});