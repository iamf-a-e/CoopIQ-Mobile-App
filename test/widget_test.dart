import 'package:flutter_test/flutter_test.dart';
import 'package:coopiq/core/models.dart';

void main() {
  test('broiler vaccination schedule is ordered', () {
    final days = broilerVaccination.map((v) => v.day).toList();
    expect(days, [...days]..sort());
  });
}
