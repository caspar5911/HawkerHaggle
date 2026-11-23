import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'screens.dart';
import 'widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(HawkerHaggleApp(api: Api()));
}

class HawkerHaggleApp extends StatelessWidget {
  const HawkerHaggleApp({super.key, required this.api});
  final Api api;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hawker Haggle',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Fredoka',
        colorScheme: ColorScheme.fromSeed(seedColor: Palette.teal, surface: Palette.cream),
        scaffoldBackgroundColor: Palette.cream,
        snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      ),
      home: MarketScreen(api: api),
    );
  }
}
