import 'package:flutter_test/flutter_test.dart';
import 'package:vault/app/constants/open_source.dart';

void main() {
  test('credits the app and compatible gateways with public repository urls', () {
    expect(kThisProject.url, 'https://github.com/tianyugithub/yucon');
    expect(kThisProject.license, 'MIT');
    expect(
      kCompatibleGateways.map((item) => item.url),
      [
        'https://github.com/QuantumNous/new-api',
        'https://github.com/Wei-Shaw/sub2api',
      ],
    );
    expect(kCompatibleGateways.map((item) => item.license).toSet(), {
      'AGPL-3.0',
      'LGPL-3.0',
    });
    expect(kThisProject.displayUrl, 'github.com/tianyugithub/yucon');
    expect(kOpenSourceDisclaimer.contains('无隶属'), isTrue);
    expect(kAppVersion, isNotEmpty);
  });
}
