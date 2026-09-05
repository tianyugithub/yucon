import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vault/app/modules/vault_store.dart';
import 'package:vault/screens/data_backup_screen.dart';
import 'package:vault/screens/themes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('backup screen shows import backup export actions', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => Themes()),
          ChangeNotifierProvider(create: (_) => VaultStore()),
        ],
        child: const MaterialApp(home: DataBackupScreen()),
      ),
    );
    await tester.pump();
    expect(find.text('备份'), findsWidgets);
    expect(find.text('导出'), findsOneWidget);
    expect(find.text('导入'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2300));
  });
}
