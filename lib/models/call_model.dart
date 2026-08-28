import 'package:flutter/foundation.dart';

enum CallState {
  ringing,
  accepting,
  connected,
  ending,
  ended,
  rejected,
  cancelled,
  failed,
}

extension CallStateExtension on CallState {
  bool get isTerminal {
    return this == CallState.ended ||
        this == CallState.rejected ||
        this == CallState.cancelled ||
        this == CallState.failed;
  }

  /// Verifies if a transition from this state to [target] is valid.
  bool canTransitionTo(CallState target) {
    if (this == target) return true; // Idempotent same-state transitions
    if (isTerminal) return false;    // Once in terminal state, it cannot change

    switch (this) {
      case CallState.ringing:
        return target == CallState.accepting ||
            target == CallState.rejected ||
            target == CallState.cancelled ||
            target == CallState.failed ||
            target == CallState.ended;
      case CallState.accepting:
        // Accepting a cancelled call must fail safely (we'll guard this)
        return target == CallState.connected ||
            target == CallState.failed ||
            target == CallState.cancelled ||
            target == CallState.ended;
      case CallState.connected:
        return target == CallState.ending ||
            target == CallState.ended ||
            target == CallState.failed;
      case CallState.ending:
        return target == CallState.ended;
      default:
        return false;
    }
  }

  String get displayName {
    return name.toUpperCase();
  }
}

class CallModel {
  final String callId;
  final String callerId;
  final String receiverId;
  final CallState state;
  final DateTime createdAt;
  final DateTime updatedAt;

  CallModel({
    required this.callId,
    required this.callerId,
    required this.receiverId,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
  });

  CallModel copyWith({
    String? callId,
    String? callerId,
    String? receiverId,
    CallState? state,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CallModel(
      callId: callId ?? this.callId,
      callerId: callerId ?? this.callerId,
      receiverId: receiverId ?? this.receiverId,
      state: state ?? this.state,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'call_id': callId,
      'caller_id': callerId,
      'receiver_id': receiverId,
      'state': state.name,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory CallModel.fromMap(Map<String, dynamic> map) {
    return CallModel(
      callId: map['call_id'] as String,
      callerId: map['caller_id'] as String,
      receiverId: map['receiver_id'] as String,
      state: CallState.values.byName(map['state'] as String),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CallModel &&
        other.callId == callId &&
        other.callerId == callerId &&
        other.receiverId == receiverId &&
        other.state == state &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode {
    return Object.hash(callId, callerId, receiverId, state, createdAt, updatedAt);
  }

  @override
  String toString() {
    return 'CallModel(id: $callId, caller: $callerId, receiver: $receiverId, state: ${state.name})';
  }
}
