import 'money.dart';

/// Form validators shared by all screens (SRS: input is validated).
class Validators {
  Validators._();

  static String? required(String? value, [String field = 'This field']) {
    if (value == null || value.trim().isEmpty) return '$field is required';
    return null;
  }

  static String? name(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Name is required';
    if (text.length < 2) return 'Name must be at least 2 characters';
    return null;
  }

  static String? email(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Email is required';
    final pattern = RegExp(r'^[\w.+-]+@[\w-]+(\.[\w-]+)+$');
    if (!pattern.hasMatch(text)) return 'Enter a valid email address';
    return null;
  }

  /// Bangladeshi mobile number: 01XXXXXXXXX, 8801XXXXXXXXX or +8801XXXXXXXXX
  /// (spaces and dashes allowed). Operator prefixes 013-019 are accepted.
  static String? phone(String? value) {
    final text = (value ?? '').replaceAll(RegExp(r'[\s-]'), '');
    if (text.isEmpty) return 'Phone number is required';
    if (!RegExp(r'^(\+?88)?01[3-9]\d{8}$').hasMatch(text)) {
      return 'Enter a valid mobile number (e.g. 01712345678)';
    }
    return null;
  }

  static String? password(String? value) {
    final text = value ?? '';
    if (text.isEmpty) return 'Password is required';
    if (text.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  static String? Function(String?) confirmPassword(String Function() original) {
    return (value) {
      if (value == null || value.isEmpty) return 'Please confirm your password';
      if (value != original()) return 'Passwords do not match';
      return null;
    };
  }

  static String? address(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Delivery address is required';
    if (text.length < 8) return 'Please enter a more complete address';
    return null;
  }

  static String? price(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Price is required';
    final minor = Money.tryParse(text);
    if (minor == null) return 'Enter a valid amount (e.g. 450 or 450.50)';
    if (minor <= 0) return 'Price must be greater than 0';
    if (minor > 1000000000) return 'Price is too large';
    return null;
  }

  /// Product codes: letters, digits and hyphens, e.g. FAB-COT-001.
  static String? productCode(String? value) {
    final text = (value ?? '').trim().toUpperCase();
    if (text.isEmpty) return 'Product code is required';
    if (text.length < 3 || text.length > 24) return 'Use 3-24 characters';
    if (!RegExp(r'^[A-Z0-9]+(-[A-Z0-9]+)*$').hasMatch(text)) {
      return 'Use letters, digits and single hyphens only';
    }
    return null;
  }

  /// Optional order note, kept short so it fits on a delivery slip.
  static String? note(String? value) {
    if ((value ?? '').length > 300) return 'Please keep notes under 300 characters';
    return null;
  }

  static String? voucherCode(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Enter a voucher code';
    if (!RegExp(r'^[A-Za-z0-9_-]{3,24}$').hasMatch(text)) {
      return 'Voucher codes use letters, numbers, - or _ only';
    }
    return null;
  }
}
