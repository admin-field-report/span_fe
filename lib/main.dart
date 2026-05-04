import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'core/router.dart';
import 'core/theme_controller.dart';
import 'core/storage_service.dart';
import 'screens/auth/controllers/auth_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  // Initialize Storage first
  await StorageService.init();

  // Then check auth state & initialize the refresh timer logic
  await authController.checkSession();

  usePathUrlStrategy();
  runApp(const FieldReportApp());
}

class FieldReportApp extends StatefulWidget {
  const FieldReportApp({super.key});

  @override
  State<FieldReportApp> createState() => _FieldReportAppState();
}

class _FieldReportAppState extends State<FieldReportApp> with WidgetsBindingObserver {
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      authController.manageSession();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) {
        return MaterialApp.router(
          title: 'Span Inspect',
          debugShowCheckedModeBanner: false,
          routerConfig: router,
          themeMode: themeController.themeMode,
          theme: themeController.getTheme(Brightness.light),
          darkTheme: themeController.getTheme(Brightness.dark),
        );
      },
    );
  }
}
