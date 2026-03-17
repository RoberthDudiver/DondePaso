import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';

import 'footprint/footprint_screen.dart';
import 'i18n/app_strings.dart';
import 'security/app_security_gate.dart';
import 'telemetry/firebase_telemetry.dart';

class DondePasoApp extends StatelessWidget {
  const DondePasoApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF9EE37D),
      brightness: Brightness.dark,
    );
    final baseTextTheme = GoogleFonts.spaceGroteskTextTheme().apply(
      bodyColor: Colors.white,
      displayColor: Colors.white,
    );

    return MaterialApp(
      title: 'DondePaso',
      debugShowCheckedModeBanner: false,
      navigatorObservers: [
        if (FirebaseTelemetry.observer != null) FirebaseTelemetry.observer!,
      ],
      supportedLocales: const [Locale('en'), Locale('es')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: baseScheme.copyWith(
          surface: const Color(0xFF060606),
          primary: const Color(0xFFB8FF8C),
          secondary: const Color(0xFF7BE0FF),
          tertiary: const Color(0xFFFFD36F),
        ),
        scaffoldBackgroundColor: const Color(0xFF030303),
        textTheme: baseTextTheme,
        appBarTheme: AppBarTheme(
          backgroundColor: const Color(0xFF030303),
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          centerTitle: false,
          titleTextStyle: baseTextTheme.titleLarge?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      onGenerateTitle: (context) => context.strings.appTitle,
      home: const AppSecurityGate(child: FootprintScreen()),
    );
  }
}
