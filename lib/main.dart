import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'services/notifications.dart';
import 'services/background.dart';
import 'services/db.dart';
import 'services/settings.dart';
import 'services/ui_state.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:animations/animations.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'screens/calendar_screen.dart';
import 'screens/stats_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Notifier.init();
  await BackgroundScheduler.init();
  runApp(const SplashApp());
}

class SplashApp extends StatefulWidget {
  const SplashApp({super.key});
  @override
  State<SplashApp> createState() => _SplashAppState();
}

class _SplashAppState extends State<SplashApp> {
  bool _done = false;
  @override
  void initState() {
    super.initState();
    // Short splash then show App
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _done = true);
    });
  }
  @override
  Widget build(BuildContext context) {
    if (_done) return const App();
    return MaterialApp(
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: Scaffold(
        backgroundColor: const Color(0xFF0f172a),
        body: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.85, end: 1),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutBack,
            builder: (_, scale, child) => Opacity(
              opacity: (((scale - 0.85) / (1 - 0.85))).clamp(0.0, 1.0),
              child: Transform.scale(scale: scale, child: child),
            ),
            child: Image.asset(
              'assets/icon/app_icon.png',
              width: 128,
              height: 128,
              errorBuilder: (_, __, ___) => const Icon(Icons.favorite, size: 96, color: Colors.white70),
            ),
          ),
        ),
      ),
    );
  }
}

class App extends StatefulWidget {
  const App({super.key});
  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  int _index = 0;
  final _navKey = GlobalKey<NavigatorState>();
  final ValueNotifier<int> _expandBatchSignal = ValueNotifier<int>(0);
  DateTime? _lastBack;

  List<Widget> get _pages => [
        HomeScreen(expandBatchSignal: _expandBatchSignal),
    const StatsScreen(),
        const CalendarScreen(),
        const SettingsScreen(),
      ];

  @override
  void initState() {
    super.initState();
    // Configure notification response handling
    Notifier.onResponse = _handleNotificationResponse;
    // Load UI state (compact, theme)
    UiState.instance.load();
    // Schedule daily job at user-selected time
    _loadAndSchedule();
  }

  Future<void> _loadAndSchedule() async {
    final t = await SettingsService.getDailyReminderTime();
    await BackgroundScheduler.scheduleDailyAt(t);
  }

  Future<void> _handleNotificationResponse(NotificationResponse r) async {
    final ctx = _navKey.currentContext;
    if (ctx == null) return;
    // Open batch from summary tap
    if (r.payload == 'open:batch') {
      setState(() => _index = 0);
      _expandBatchSignal.value++;
      return;
    }
    // Snooze action picker
    final id = Notifier.extractPersonId(r);
    if (id != null && (r.actionId?.startsWith('snooze_') ?? false)) {
      await _showSnoozePicker(ctx, id);
      return;
    }
  }

  Future<void> _showSnoozePicker(BuildContext context, int personId) async {
    Duration? picked;
    picked = await showModalBottomSheet<Duration>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final now = DateTime.now();
        Duration untilNextSunday() {
          final daysUntil = (DateTime.sunday - now.weekday + 7) % 7;
          final days = daysUntil == 0 ? 7 : daysUntil;
          return Duration(days: days);
        }
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: Text('Snooze')),
              ListTile(title: const Text('30 minutes'), onTap: () => Navigator.pop(ctx, const Duration(minutes: 30))),
              ListTile(title: const Text('1 hour'), onTap: () => Navigator.pop(ctx, const Duration(hours: 1))),
              ListTile(title: const Text('3 hours'), onTap: () => Navigator.pop(ctx, const Duration(hours: 3))),
              ListTile(title: const Text('Tomorrow'), onTap: () => Navigator.pop(ctx, const Duration(days: 1))),
              ListTile(title: const Text('Next Sunday'), onTap: () => Navigator.pop(ctx, untilNextSunday())),
              ListTile(title: const Text('Next week'), onTap: () => Navigator.pop(ctx, const Duration(days: 7))),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (picked != null) {
      final db = await AppDb.instance;
      await PersonRepo(db).snooze(personId, picked);
      if (mounted) {
        ScaffoldMessenger.of(_navKey.currentContext!).showSnackBar(const SnackBar(content: Text('Snoozed')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Ensure background daily job is scheduled
    BackgroundScheduler.scheduleDaily();
    return ValueListenableBuilder(
      valueListenable: UiState.instance.backgroundColor,
      builder: (context, bg, _) {
        return ValueListenableBuilder(
          valueListenable: UiState.instance.cardColor,
          builder: (context, card, __) {
            final colorScheme = ColorScheme.fromSeed(brightness: Brightness.dark, seedColor: Colors.cyanAccent);
            return MaterialApp(
              title: 'KeepInTouch',
              navigatorKey: _navKey,
              theme: ThemeData(
                useMaterial3: true,
                brightness: Brightness.dark,
                colorScheme: colorScheme,
                scaffoldBackgroundColor: bg,
                appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0),
                cardTheme: CardThemeData(
                  color: card,
                  elevation: 2,
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
                ),
                textTheme: GoogleFonts.interTextTheme(ThemeData(brightness: Brightness.dark).textTheme),
                pageTransitionsTheme: const PageTransitionsTheme(builders: {
                  TargetPlatform.android: SharedAxisPageTransitionsBuilder(transitionType: SharedAxisTransitionType.scaled),
                }),
              ),
              home: WillPopScope(
        onWillPop: () async {
          // If not on Home tab, go back to Home instead of exiting
          if (_index != 0) {
            setState(() => _index = 0);
            return false;
          }
          final now = DateTime.now();
          if (_lastBack == null || now.difference(_lastBack!) > const Duration(seconds: 2)) {
            _lastBack = now;
            ScaffoldMessenger.of(_navKey.currentContext!).showSnackBar(const SnackBar(content: Text('Press back again to exit')));
            return false;
          }
          return true; // exit app
        },
        child: Scaffold(
          extendBodyBehindAppBar: true,
          body: _pages[_index],
          bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.query_stats), label: 'Stats'),
            NavigationDestination(icon: Icon(Icons.calendar_today), label: 'Calendar'),
            NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
          ],
          onDestinationSelected: (i) => setState(() => _index = i),
          ),
        ),
              ),
            );
          },
        );
      },
    );
  }
}
