import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/app_database.dart';
import 'screens/home_screen.dart';
import 'services/theme_preference.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final database = AppDatabase();
  await database.open();
  final themePreference = await ThemePreference.load(database);
  runApp(
    PocketExpenseApp(database: database, themePreference: themePreference),
  );
}

class PocketExpenseApp extends StatelessWidget {
  const PocketExpenseApp({
    super.key,
    required this.database,
    required this.themePreference,
  });

  final AppDatabase database;
  final ThemePreference themePreference;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: themePreference,
    builder: (context, _) => MaterialApp(
      title: 'Pocket Expense',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themePreference.isDark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
            statusBarBrightness: dark ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: Theme.of(context).scaffoldBackgroundColor,
            systemNavigationBarIconBrightness: dark
                ? Brightness.light
                : Brightness.dark,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: HomeScreen(
        database: database,
        isDarkMode: themePreference.isDark,
        onDarkModeChanged: themePreference.setDark,
      ),
    ),
  );
}
