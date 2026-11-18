import 'dart:math';

/// Time-ordered UUID (version 7): 48-bit Unix milliseconds, then random bits,
/// so new rows land at the end of indexes.
String uuidV7(DateTime time, Random random) {
  final ms = time.toUtc().millisecondsSinceEpoch;
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  for (var i = 0; i < 6; i++) {
    bytes[i] = (ms >> (8 * (5 - i))) & 0xff;
  }
  bytes[6] = 0x70 | (bytes[6] & 0x0f); // version 7
  bytes[8] = 0x80 | (bytes[8] & 0x3f); // RFC 4122 variant
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
