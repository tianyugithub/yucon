import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vault/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app boots', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const YuconApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1400));
    expect(find.text('钥仓'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2800));
  });
}
