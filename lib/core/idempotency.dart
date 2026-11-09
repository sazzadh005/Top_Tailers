import 'dart:math';

/// A random key (24 hex characters) that makes a retried request safe: the
/// server returns the original result instead of repeating the action.
String newIdempotencyKey() {
  final random = Random.secure();
  final buffer = StringBuffer();
  for (var i = 0; i < 12; i++) {
    buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}
