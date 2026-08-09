import 'package:openminis_core/openminis.dart';
import 'package:test/test.dart';

void main() {
  group('SecretResolver web-safety', () {
    test('has() does not throw when env provider absent (web)', () {
      // Simulate web: no env provider is registered.
      SecretResolver.seed(const {}); // ensure no stale overrides
      // Must not throw, even with no key.
      expect(SecretResolver.has('ANYTHING_THAT_IS_NOT_SET'), isFalse);
      expect(SecretResolver.lookup('ANYTHING_THAT_IS_NOT_SET'), isNull);
    });

    test('seeded overrides are visible and never throw', () {
      SecretResolver.seed({'WEB_TEST_KEY': 'secret-value'});
      expect(SecretResolver.has('WEB_TEST_KEY'), isTrue);
      expect(SecretResolver.lookup('WEB_TEST_KEY'), 'secret-value');
    });

    test('does not echo the secret value in has()', () {
      SecretResolver.seed({'SENSITIVE': 'do-not-log'});
      // has() only returns a bool.
      expect(SecretResolver.has('SENSITIVE'), isA<bool>());
    });
  });
}
