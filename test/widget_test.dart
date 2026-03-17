import 'package:dondepaso/src/app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('app boots', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const DondePasoApp());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(DondePasoApp), findsOneWidget);
  });
}
