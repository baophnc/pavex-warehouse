import 'package:flutter_test/flutter_test.dart';
import 'package:pavex_warehouse/ui/password_screens.dart';

void main() {
  test('the reset token is read from the emailed link or taken as typed', () {
    expect(extractResetToken('http://localhost:3001/reset-password?token=abc_123-XYZ'), 'abc_123-XYZ');
    expect(extractResetToken('  abc_123-XYZ  '), 'abc_123-XYZ');
  });
}
