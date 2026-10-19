/// Money is stored as an integer number of paisa (1 BDT = 100 paisa) so that
/// totals, percentages and discounts never suffer floating-point drift.
class Money {
  Money._();

  /// Parses user input such as "450", "450.5" or "1,250.75" into paisa.
  /// Returns null for anything that is not a plain non-negative amount.
  static int? tryParse(String input) {
    final text = input.trim().replaceAll(',', '');
    final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(text);
    if (match == null) return null;
    final whole = int.tryParse(match.group(1)!);
    if (whole == null) return null;
    final fraction = (match.group(2) ?? '').padRight(2, '0');
    return whole * 100 + int.parse(fraction.isEmpty ? '0' : fraction);
  }

  /// Text suitable for an editable field: 45000 -> "450", 45050 -> "450.50".
  static String toInput(int minor) {
    final whole = minor ~/ 100;
    final fraction = minor % 100;
    if (fraction == 0) return '$whole';
    return '$whole.${fraction.toString().padLeft(2, '0')}';
  }
}
