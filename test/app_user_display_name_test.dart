import 'package:fixnow/core/enums/user_role.dart';
import 'package:fixnow/features/auth/domain/app_user.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AppUser user({required String name, required String email}) => AppUser(
        uid: 'technician-1',
        name: name,
        email: email,
        phone: '',
        role: UserRole.technician,
        createdAt: DateTime(2026, 10, 16),
        isActive: true,
      );

  test('uses the stored name when a profile is complete', () {
    expect(user(name: '  Hari Dinesh ', email: 'hari@example.com').displayName,
        'Hari Dinesh');
  });

  test('uses an email identity when a legacy profile has no name', () {
    expect(user(name: '', email: 'hari.dinesh@example.com').displayName,
        'hari.dinesh');
  });

  test('has a visible fallback when neither name nor email exists', () {
    expect(user(name: '', email: '').displayName, 'Unnamed technician');
  });
}
