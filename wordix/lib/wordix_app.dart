import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'auth/auth_gate.dart';
import 'theme/wordix_theme_controller.dart';

class WordixRoot extends StatefulWidget {
  const WordixRoot({super.key});

  @override
  State<WordixRoot> createState() => _WordixRootState();
}

class _WordixRootState extends State<WordixRoot> {
  late final WordixThemeController _themeController;

  @override
  void initState() {
    super.initState();
    _themeController = WordixThemeController();
  }

  @override
  void dispose() {
    _themeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WordixThemeBinding(
      controller: _themeController,
      child: AnimatedBuilder(
        animation: _themeController,
        builder: (context, _) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lexiconClearLight(),
            darkTheme: AppTheme.dark(),
            themeMode: _themeController.useClearLightTheme ? ThemeMode.light : ThemeMode.dark,
            home: const AuthGate(),
          );
        },
      ),
    );
  }
}
