import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irigatie_app/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders irrigation dashboard', (tester) async {
    await tester.pumpWidget(
      IrrigationApp(initialSnapshot: IrrigationSnapshot.sample()),
    );

    expect(find.text('Irigatie'), findsOneWidget);
    expect(find.text('Status'), findsWidgets);
    expect(find.text('Daemon'), findsOneWidget);
    expect(find.text('Program curent'), findsOneWidget);
    expect(find.text('Ploaie 24h'), findsOneWidget);
    expect(find.text('Open-Meteo'), findsOneWidget);
    expect(find.text('Hardware'), findsOneWidget);
    expect(find.text('2.8 mm'), findsOneWidget);
    expect(find.text('0.4 mm'), findsOneWidget);
  });

  testWidgets('switches theme mode from the header', (tester) async {
    await tester.pumpWidget(
      IrrigationApp(initialSnapshot: IrrigationSnapshot.sample()),
    );

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );

    await tester.tap(find.byTooltip('Dark'));
    await tester.pump();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
  });
}
