import 'package:flutter_test/flutter_test.dart';
import 'package:top_tailers_/core/format.dart';
import 'package:top_tailers_/core/validators.dart';

void main() {
  group('Validators', () {
    test('email', () {
      expect(Validators.email(''), isNotNull);
      expect(Validators.email('not-an-email'), isNotNull);
      expect(Validators.email('user@example.com'), isNull);
    });

    test('phone accepts Bangladeshi mobile formats', () {
      expect(Validators.phone('01712345678'), isNull);
      expect(Validators.phone('+8801712345678'), isNull);
      expect(Validators.phone('12345'), isNotNull);
      expect(Validators.phone(''), isNotNull);
    });

    test('password needs at least 6 characters', () {
      expect(Validators.password('12345'), isNotNull);
      expect(Validators.password('123456'), isNull);
    });

    test('confirm password must match', () {
      final validator = Validators.confirmPassword(() => 'secret1');
      expect(validator('other'), isNotNull);
      expect(validator('secret1'), isNull);
    });

    test('price must be a positive number', () {
      expect(Validators.price('abc'), isNotNull);
      expect(Validators.price('0'), isNotNull);
      expect(Validators.price('-5'), isNotNull);
      expect(Validators.price('450'), isNull);
    });
  });

  group('Formatting', () {
    test('formatMoney adds separators', () {
      expect(formatMoney(450), '৳450');
      expect(formatMoney(12500), '৳12,500');
      expect(formatMoney(1234567), '৳1,234,567');
    });
  });
}
