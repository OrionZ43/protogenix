import 'package:flutter_test/flutter_test.dart';
import 'package:protogenix/core/utils/track_time.dart';

void main() {
  test('до часа — как раньше', () {
    expect(formatTrackTime(Duration.zero), '00:00');
    expect(formatTrackTime(const Duration(minutes: 3, seconds: 33)), '03:33');
    expect(formatTrackTime(const Duration(minutes: 59, seconds: 59)), '59:59');
  });

  test('от часа — с часами, а не по модулю', () {
    // Раньше двухчасовой сборник показывался как «00:00»
    expect(formatTrackTime(const Duration(hours: 2)), '2:00:00');
    expect(formatTrackTime(const Duration(hours: 1, minutes: 5, seconds: 7)),
        '1:05:07');
  });

  test('отрицательная позиция — ноль', () {
    expect(formatTrackTime(const Duration(seconds: -3)), '00:00');
  });
}
