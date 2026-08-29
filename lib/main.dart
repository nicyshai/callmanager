import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/logger.dart';
import 'core/theme.dart';
import 'services/call_controller.dart';
import 'services/signaling_service.dart';
import 'widgets/callkit_overlay.dart';
import 'widgets/device_panel.dart';
import 'widgets/log_console.dart';
import 'widgets/simulator_panel.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: CallManagerApp(),
    ),
  );
}

class CallManagerApp extends StatelessWidget {
  const CallManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CallManager Lifecycle Sim',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light, // Defaulting to light for Truecaller look
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with SingleTickerProviderStateMixin {
  TabController? _tabController;
  bool _showConsole = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    
    // Asynchronously startup the local signaling pipeline
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final server = ref.read(signalingServerProvider);
      await server.start();
      
      // Allow server to bind before clients connect
      await Future.delayed(const Duration(milliseconds: 200));
      
      // Connect signaling clients
      ref.read(localSignalingClientProvider).connect();
      ref.read(remoteSignalingClientProvider).connect();
      
      // Initialize call controller state
      ref.read(callControllerProvider.notifier).init();
    });
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "CallManager",
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
        actions: [
          IconButton(
            icon: Icon(_showConsole ? Icons.terminal : Icons.terminal_outlined),
            onPressed: () => setState(() => _showConsole = !_showConsole),
            tooltip: "Toggle System Console",
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.read(callControllerProvider.notifier).clearHistory();
              ref.read(logProvider.notifier).clearLogs();
            },
            tooltip: "Clear History & Logs",
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
          unselectedLabelColor: Colors.white.withValues(alpha: 0.7),
          indicatorSize: TabBarIndicatorSize.tab,
          tabs: const [
            Tab(text: "CALLS"),
            Tab(text: "SIMULATOR"),
          ],
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: const [
                    Padding(
                      padding: EdgeInsets.all(12.0),
                      child: DevicePanel(),
                    ),
                    Padding(
                      padding: EdgeInsets.all(12.0),
                      child: SimulatorPanel(),
                    ),
                  ],
                ),
              ),
              if (_showConsole)
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: LogConsole(),
                ),
            ],
          ),
          
          // Custom sliding in-app CallKit Overlay Simulator
          // This stays in Stack to cover the whole screen when active
          const CallKitOverlay(),
        ],
      ),
    );
  }
}
