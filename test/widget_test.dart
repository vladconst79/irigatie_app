import 'package:flutter_test/flutter_test.dart';
import 'package:irigatie_app/main.dart';

void main() {
  testWidgets('renders irrigation dashboard', (tester) async {
    await tester.pumpWidget(
      IrrigationApp(initialSnapshot: IrrigationSnapshot.sample()),
    );

    expect(find.text('Irigatie'), findsOneWidget);
    expect(find.text('Status'), findsWidgets);
    expect(find.text('Daemon'), findsOneWidget);
    expect(find.text('Program curent'), findsOneWidget);
  });
}
