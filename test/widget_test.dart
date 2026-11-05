import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:print_app/app.dart';
import 'package:print_app/providers/settings_provider.dart';
import 'package:print_app/providers/server_provider.dart';
import 'package:print_app/providers/printer_provider.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ChangeNotifierProvider(create: (_) => ServerProvider()),
          ChangeNotifierProvider(create: (_) => PrinterProvider()),
        ],
        child: const PrintAgentApp(),
      ),
    );
    // La app debe renderizar sin lanzar excepciones
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
