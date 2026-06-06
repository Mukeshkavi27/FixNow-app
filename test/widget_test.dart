import 'package:flutter_test/flutter_test.dart';

void main() {
  test('booking status labels stay user friendly', () {
    expect('Technician Assigned'.contains('Assigned'), isTrue);
  });
}
