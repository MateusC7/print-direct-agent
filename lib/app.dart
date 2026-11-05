import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'providers/settings_provider.dart';
import 'ui/pages/home_page.dart';

import 'ui/pages/customer_presentation_page.dart';

/// Raíz de la aplicación. Configura los providers y el ThemeData.
class PrintAgentApp extends StatelessWidget {
  const PrintAgentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settings, _) {
        return MaterialApp(
          key: ValueKey('${settings.lang}_${settings.theme}'),
          title: 'Software Restaurante',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          locale: Locale(settings.lang),
          themeMode:
              settings.isDark ? ThemeMode.dark : ThemeMode.light,
          home: const HomePage(),
          routes: {
            'presentation': (context) => const CustomerPresentationPage(),
          },
        );
      },
    );
  }
}
