import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:thottam/core/ids/uuid_v7.dart';

void main() {
  test('format, version and variant', () {
    final id = uuidV7(DateTime.utc(2026, 11, 17), Random(1));
    expect(
      id,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
  });

  test('later times sort later', () {
    final r = Random(1);
    final a = uuidV7(DateTime.utc(2026, 11, 17, 10), r);
    final b = uuidV7(DateTime.utc(2026, 11, 17, 11), r);
    expect(a.compareTo(b), lessThan(0));
  });
}
