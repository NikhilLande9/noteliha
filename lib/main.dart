import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import 'firebase_options.dart';
import 'models.dart';
import 'theme_helper.dart';
import 'neu_theme.dart';
import 'notes_provider.dart';
import 'note_list_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // ── Crashlytics setup ──────────────────────────────────────────────────────
  // Only enable on non-web platforms — Crashlytics is not supported on web.
  if (!kIsWeb) {
    // Forward all uncaught Flutter framework errors to Crashlytics.
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

    // Forward all uncaught async/platform errors to Crashlytics.
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }

  await Hive.initFlutter();
  Hive.registerAdapter(NoteAdapter());

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
            create: (_) => NotesProvider()..init(), lazy: false),
        ChangeNotifierProvider(create: (_) => AppSettingsProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final seed = AppSettingsProvider.seedColor(settings.appTheme);

    // Neu.base() already reflects the active visual theme via Neu.setTheme().
    final lightBase   = Neu.base(false);
    final darkBase    = Neu.base(true);
    final lightBorder = Neu.cardBorder(false);
    final darkBorder  = Neu.cardBorder(true);
    // Glass needs a solid background behind the blur; other themes use base.
    final isGlass = Neu.currentTheme == AppVisualTheme.glass;
    final lightScaffold = isGlass ? const Color(0xFFF0F4FF) : lightBase;
    final darkScaffold  = isGlass ? const Color(0xFF0D1117)  : darkBase;

    final baseCardTheme = CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );

    return MaterialApp(
      title: 'noteliha',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: seed,
        brightness: Brightness.light,
        scaffoldBackgroundColor: lightScaffold,
        dialogTheme: DialogThemeData(backgroundColor: lightBase),
        appBarTheme: AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: lightBase,
          titleTextStyle: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Neu.textPrimary(false),
              letterSpacing: -0.5),
        ),
        cardTheme: baseCardTheme.copyWith(
          color: lightBase,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: lightBorder),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: seed,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: darkScaffold,
        dialogTheme: DialogThemeData(backgroundColor: darkBase),
        appBarTheme: AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: darkBase,
          titleTextStyle: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Neu.textPrimary(true),
              letterSpacing: -0.5),
        ),
        cardTheme: baseCardTheme.copyWith(
          color: darkBase,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: darkBorder),
        ),
      ),
      themeMode: settings.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: const NoteListScreen(),
    );
  }
}