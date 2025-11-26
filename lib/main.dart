import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'dart:io';
import 'pages/home_page.dart';
import 'pages/process_page.dart';
import 'pages/settings_page.dart';
import 'pages/rules_page.dart';
import 'pages/rule_edit_page.dart';
import 'services/notification_service.dart';
import 'services/clipboard_service.dart';
import 'services/theme_service.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

// Check if running on desktop
bool get isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

// Check if running on mobile
bool get isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Desktop-specific initialization
  if (isDesktop) {
    await windowManager.ensureInitialized();

    WindowOptions windowOptions = const WindowOptions(
      size: Size(800, 600),
      center: true,
      // skipTaskbar: true,
      titleBarStyle: TitleBarStyle.normal,
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.setPreventClose(true);
    });
  }

  await NotificationService.initialize();
  await ClipboardService.initialize();
  await ThemeService.initialize();
  runApp(const LinkPureApp());
}

final _router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomePage()),
    GoRoute(
      path: '/process',
      builder: (context, state) {
        final url = state.uri.queryParameters['url'];
        return ProcessPage(url: url);
      },
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsPage(),
    ),
    GoRoute(path: '/rules', builder: (context, state) => const RulesPage()),
    GoRoute(
      path: '/rules/edit',
      builder: (context, state) {
        final ruleId = state.uri.queryParameters['id'];
        return RuleEditPage(ruleId: ruleId);
      },
    ),
  ],
);

class LinkPureApp extends StatefulWidget {
  const LinkPureApp({super.key});

  @override
  State<LinkPureApp> createState() => _LinkPureAppState();
}

class _LinkPureAppState extends State<LinkPureApp>
    with WindowListener, TrayListener {
  @override
  void initState() {
    super.initState();

    // 监听主题变化
    ThemeService.instance.addListener(_onThemeChanged);

    if (isDesktop) {
      // Desktop: Initialize window manager and tray
      windowManager.addListener(this);
      trayManager.addListener(this);
      _initSystemTray();

      // Hide window after initialization
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future.delayed(const Duration(milliseconds: 500));
        // TODO: 有 bug，无法正确在启动应用后立刻隐藏窗口，会出现闪烁，暂时注释掉
        // await windowManager.hide();
      });
    } else if (isMobile) {
      // Mobile: Handle shared intents
      _handleSharedIntent();
    }
  }

  void _onThemeChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    ThemeService.instance.removeListener(_onThemeChanged);
    if (isDesktop) {
      windowManager.removeListener(this);
      trayManager.removeListener(this);
    }
    super.dispose();
  }

  // Mobile: Handle shared intents
  void _handleSharedIntent() {
    // Handle shared text when app is opened via share
    ReceiveSharingIntent.instance.getInitialMedia().then((
      List<SharedMediaFile> value,
    ) {
      if (value.isNotEmpty) {
        final sharedText = value.first.path;
        if (sharedText.isNotEmpty) {
          // Navigate to process page with shared URL
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _router.go('/process?url=${Uri.encodeComponent(sharedText)}');
          });
        }
      }
    });

    // Listen for shared text while app is running
    ReceiveSharingIntent.instance.getMediaStream().listen(
      (List<SharedMediaFile> value) {
        if (value.isNotEmpty) {
          final sharedText = value.first.path;
          if (sharedText.isNotEmpty) {
            _router.pushReplacement(
              '/process?url=${Uri.encodeComponent(sharedText)}',
            );
          }
        }
      },
      onError: (err) {
        debugPrint('Error receiving shared intent: $err');
      },
    );
  }

  // Desktop: Window close handler
  @override
  void onWindowClose() async {
    // Prevent window from closing, just hide it
    await windowManager.hide();
  }

  // Desktop: Initialize system tray
  Future<void> _initSystemTray() async {
    await trayManager.setIcon(
      Platform.isWindows ? 'assets/appicon.ico' : 'assets/appicon.png',
      isTemplate: true,
    );

    Menu menu = Menu(
      items: [
        MenuItem(key: 'open_window', label: 'Open LinkPure'),
        MenuItem(key: 'quit', label: 'Quit'),
      ],
    );
    await trayManager.setContextMenu(menu);
  }

  // Desktop: Tray icon click handlers
  @override
  void onTrayIconMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'open_window':
        windowManager.show();
        windowManager.focus();
        break;
      case 'quit':
        windowManager.destroy();
        exit(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'LinkPure',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueGrey,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeService.instance.themeMode,
      routerConfig: _router,
    );
  }
}
