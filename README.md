# CallManager Reliable Lifecycle Simulator

A Flutter project demonstrating a reliable incoming-call system using CallKit, SQLite, and Riverpod. Built for the Reliable Call Lifecycle Management assignment.

## 🚀 Architecture Overview

This project follows a clean, layered architecture using **Riverpod** for state management and dependency injection.

- **UI Layer (Widgets)**: Contains `DevicePanel` (user_001), `SimulatorPanel` (user_002), and `LogConsole`. They interact with the logic layer strictly through providers.
- **Logic Layer (Controllers)**: 
  - `CallController`: Manages the state machine for the local user.
  - `RemoteSimulationController`: Orchestrates network events from the simulated remote user.
- **Service Layer**:
  - `CallKitService`: Bridges Flutter with the native Android/iOS CallKit plugins, including an in-app fallback overlay for non-mobile platforms.
  - `SignalingServer/Client`: A local WebSocket implementation that simulates network signaling without needing an external server.
- **Data Layer (Repository)**:
  - `CallRepository`: Handles SQLite operations with transactional integrity and transition validation.

## 🔄 State Machine

The call lifecycle is governed by a strict state machine defined in `lib/models/call_model.dart`:

**RINGING** → **ACCEPTING** → **CONNECTED** → **ENDING** → **ENDED**

Additional terminal states:
- **REJECTED**: User manually declined.
- **CANCELLED**: Remote caller hung up before answer.
- **FAILED**: System error or app crash during call.

**Rules**:
1. Transitions to terminal states are irreversible.
2. Any transition must be validated by `canTransitionTo()` before execution.
3. Out-of-order events (e.g., `START` after `END`) are caught and logged as ignored.

## 🛡️ Reliability & Idempotency Strategy

### 1. Duplicate & Out-of-Order Events
Every network event includes a `call_id`. The `CallRepository` uses SQLite **transactions** with a `UNIQUE` constraint on `call_id`. 
- `createCall`: If a call record already exists, the database operation returns the existing record instead of creating a duplicate.
- `CallController`: Before triggering CallKit, it verifies if the call is already in a state that justifies the prompt.

### 2. Race Conditions
The "Remote Cancel vs Local Accept" race is handled by:
- **Atomic Transitions**: SQLite transactions ensure that if a call is marked `CANCELLED` by the remote user, the local `ACCEPT` operation will fail the `canTransitionTo` check.
- **Post-Handshake Verification**: After the simulated 1.5s handshake delay, the controller re-verifies the database state before transitioning to `CONNECTED`.

### 3. Termination Strategy
- Termination events (`end_call`) are **idempotent**. If the call is already `ENDED`, subsequent `end_call` events are ignored to prevent infinite loops.
- Simultaneous termination from both sides resolves deterministically because the first side to update the SQLite state "wins", and the second side's attempt is ignored as a same-state transition.

### 4. Restart Handling (SQLite Recovery)
On app startup or re-initialization:
- `recoverActiveCalls()` is called.
- It queries SQLite for any records NOT in a terminal state (ringing, connected, etc.).
- These "dangling" calls are automatically transitioned to **FAILED**, ensuring the app doesn't start with a ghost active call from a previous crash.

## 🛠️ Setup & Run

### Prerequisites
- Flutter SDK (latest stable recommended)
- Android Studio / VS Code
- A physical Android/iOS device (for native CallKit) or an emulator (for simulator fallback)

### Instructions
1.  **Clone & Fetch**:
    ```bash
    flutter pub get
    ```
2.  **Run**:
    ```bash
    flutter run
    ```
    *Note: The app starts a local WebSocket server on port 3000. Ensure no other service is occupying that port on your device.*

3.  **Testing**:
    - Use the **"Dial user_002"** button to initiate a call.
    - Use the **"Remote Simulator"** tab/panel to trigger edge cases like duplicate events or out-of-order packets.
    - View real-time state transitions in the **Live System Log Console** at the bottom.

## 🧪 Unit Tests

Run the comprehensive lifecycle tests:
```bash
flutter test test/widget_test.dart
```
**Tested Scenarios**:
- Strict state transition rule enforcement.
- Duplicate record creation blocking.
- Terminal state blockade.
- SQLite recovery from non-terminal states.
- Remote cancel race condition resolution.
- Termination idempotency.
