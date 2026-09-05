import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/modules/vault_store.dart';
import 'package:vault/app/utils/quota.dart';
import 'package:vault/screens/widgets/feedback_overlay.dart';

Account _account({
  required String alias,
  required double quota,
  required AccountStatus status,
}) {
  return Account(
    id: alias,
    alias: alias,
    siteName: '测试站',
    baseUrl: 'https://example.com',
    platformType: PlatformType.newapi,
    authMode: AuthMode.password,
    userId: '1',
    username: 'demo',
    displayName: 'demo',
    email: '',
    group: 'default',
    quota: quota,
    usedQuota: 0,
    requestCount: 0,
    quotaPerUnit: 500000,
    status: status,
    checkedInToday: false,
    checkinEnabled: false,
    tags: const [],
    trend: const [],
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
  );
}

void main() {
  test('quota alerts stay silent when notifications are off', () {
    expect(
      describeQuotaAlert(
        enabled: false,
        threshold: 5,
        lowAccountNames: ['主账号'],
      ),
      isNull,
    );
  });

  test('quota alerts stay silent when nobody is low', () {
    expect(
      describeQuotaAlert(enabled: true, threshold: 5, lowAccountNames: const []),
      isNull,
    );
  });

  test('quota alerts name a single low account', () {
    expect(
      describeQuotaAlert(
        enabled: true,
        threshold: 5,
        lowAccountNames: ['主账号'],
      ),
      '主账号 额度低于 \$5.00',
    );
  });

  test('quota alerts count multiple low accounts', () {
    expect(
      describeQuotaAlert(
        enabled: true,
        threshold: 3.5,
        lowAccountNames: ['主账号', '备用'],
      ),
      '2 个账号额度低于 \$3.50',
    );
  });

  test('does not notify when the switch is off', () {
    final store = VaultStore();
    addTearDown(store.dispose);
    store.settings.notificationEnabled = false;
    store.settings.lowQuotaThreshold = 5;
    store.accounts = [
      _account(alias: '主账号', quota: 1, status: AccountStatus.low),
    ];
    expect(store.notifyQuotaAlerts(), isFalse);
    expect(store.feedback.visible, isFalse);
  });

  test('does not notify when every account is above the threshold', () {
    final store = VaultStore();
    addTearDown(store.dispose);
    store.settings.notificationEnabled = true;
    store.accounts = [
      _account(alias: '主账号', quota: 20, status: AccountStatus.active),
    ];
    expect(store.notifyQuotaAlerts(), isFalse);
    expect(store.feedback.visible, isFalse);
  });

  test('notifies after sync when an account is below the threshold', () {
    final store = VaultStore();
    addTearDown(store.dispose);
    store.settings.notificationEnabled = true;
    store.settings.lowQuotaThreshold = 5;
    store.accounts = [
      _account(alias: '主账号', quota: 1.2, status: AccountStatus.low),
    ];
    expect(store.notifyQuotaAlerts(), isTrue);
    expect(store.feedback.visible, isTrue);
    expect(store.feedback.type, FeedbackType.warning);
    expect(store.feedback.message, '主账号 额度低于 \$5.00');
    store.dismissFeedback();
  });

  testWidgets('quota alert appears on the in-app overlay', (tester) async {
    final store = VaultStore();
    addTearDown(store.dispose);
    store.settings.notificationEnabled = true;
    store.settings.lowQuotaThreshold = 5;
    store.accounts = [
      _account(alias: '主账号', quota: 1.2, status: AccountStatus.low),
    ];
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: const MaterialApp(
          home: FeedbackOverlay(child: Scaffold(body: SizedBox.expand())),
        ),
      ),
    );
    expect(store.notifyQuotaAlerts(), isTrue);
    await tester.pump();
    expect(find.text('主账号 额度低于 \$5.00'), findsOneWidget);
    store.dismissFeedback();
    await tester.pump();
    expect(find.text('主账号 额度低于 \$5.00'), findsNothing);
  });
}
