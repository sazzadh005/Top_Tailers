import 'app_strings.dart';

/// Formats an amount in paisa, e.g. 1250000 -> ৳12,500 and 45050 -> ৳450.50.
String formatMoney(int minor) {
  final negative = minor < 0;
  final abs = minor.abs();
  final whole = (abs ~/ 100).toString();
  final fraction = abs % 100;
  final buffer = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buffer.write(',');
    buffer.write(whole[i]);
  }
  final sign = negative ? '-' : '';
  final cents = fraction == 0 ? '' : '.${fraction.toString().padLeft(2, '0')}';
  return '$sign${AppStrings.currency}$buffer$cents';
}

const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String formatShortDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

String formatDateTime(DateTime d) {
  final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final minute = d.minute.toString().padLeft(2, '0');
  final suffix = d.hour >= 12 ? 'PM' : 'AM';
  return '${formatShortDate(d)}, $hour:$minute $suffix';
}

/// "just now", "5 min ago", "3 days ago" or a short date.
String formatRelative(DateTime d, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(d);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  if (diff.inDays < 7) return '${diff.inDays} d ago';
  return formatShortDate(d);
}
