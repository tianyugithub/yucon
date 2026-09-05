import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/modules/vault_store.dart';
import 'package:vault/screens/usage_log_detail_screen.dart';

void main() {
  testWidgets('usage log detail shows input and output tokens', (tester) async {
    final store = VaultStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(
          home: UsageLogDetailScreen(
            log: UsageLog(
              id: '1',
              accountId: 'missing',
              platformType: PlatformType.newapi,
              apiKeyId: '',
              apiKeyName: '默认密钥',
              model: 'gpt-4o-mini',
              time: '2026-09-05T06:12:33.000Z',
              quotaCost: 0.04,
              promptTokens: 1200,
              completionTokens: 34,
              success: true,
              group: 'default',
              content: 'complete',
            ),
            showIp: false,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('调用详情'), findsOneWidget);
    expect(find.text('输入'), findsOneWidget);
    expect(find.text('输出'), findsOneWidget);
    expect(find.text('合计'), findsOneWidget);
    expect(find.text('1,200'), findsOneWidget);
    expect(find.text('34'), findsOneWidget);
    expect(find.text('1,234'), findsOneWidget);
    expect(find.text('tokens'), findsWidgets);
    expect(find.text('gpt-4o-mini'), findsOneWidget);
  });
}
