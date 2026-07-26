import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import 'screens/home_page.dart';
import 'services/app_settings.dart';
import 'services/generic_site_api.dart';
import 'services/layout_settings.dart';
import 'services/mitao_api.dart';
import 'services/phub_api.dart';
import 'services/player_chrome.dart';
import 'services/translator.dart';
import 'services/xvideos_api.dart';

/// Video player shell (home list + site feeds + search).
class PlayerApp extends StatelessWidget {
  const PlayerApp({
    super.key,
    required this.settings,
    required this.layout,
  });

  final AppSettings settings;
  final LayoutSettings layout;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppSettings>.value(value: settings),
        ChangeNotifierProvider<LayoutSettings>.value(value: layout),
        ChangeNotifierProvider(create: (_) => PlayerChrome()),
        Provider(create: (_) => PhubApi()),
        Provider(create: (_) => XvideosApi()),
        Provider(create: (_) => MitaoApi()),
        Provider(create: (_) => GenericSiteApi()),
        Provider(create: (_) => Translator()),
      ],
      child: MaterialApp(
        title: 'ePickle',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF1E1E1E),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFFFF6B35),
            secondary: Color(0xFFFF6B35),
            surface: Color(0xFF1E1E1E),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF1E1E1E),
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: {
              TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
              TargetPlatform.android: CupertinoPageTransitionsBuilder(),
            },
          ),
        ),
        home: const HomePage(),
      ),
    );
  }
}
