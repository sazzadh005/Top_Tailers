import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/money.dart';
import '../core/theme.dart';
import '../domain/discount.dart';

/// Parses a discount value field: whole percent, or a taka amount -> paisa.
int? parseDiscountValue(DiscountKind kind, String text) {
  final t = text.trim();
  if (t.isEmpty) return null;
  return kind == DiscountKind.percent ? int.tryParse(t) : Money.tryParse(t);
}

/// Edits one discount (kind + value). When [priceMinor] is given it also
/// previews original price, discount amount and resulting price, and the
/// parent can use [validateDiscountField] to block invalid values.
class DiscountEditor extends StatelessWidget {
  const DiscountEditor({
    super.key,
    required this.kind,
    required this.valueController,
    required this.onKindChanged,
    this.priceMinor,
    this.enabled = true,
    this.onChanged,
  });

  final DiscountKind kind;
  final TextEditingController valueController;
  final ValueChanged<DiscountKind> onKindChanged;
  final int? priceMinor;
  final bool enabled;
  final VoidCallback? onChanged;

  /// Validator for the value field.
  static String? Function(String?) validator(DiscountKind kind, int? priceMinor) {
    return (text) {
      final value = parseDiscountValue(kind, text ?? '');
      if (value == null) {
        return kind == DiscountKind.percent
            ? 'Enter a whole percentage (1-99)'
            : 'Enter an amount (e.g. 50 or 50.50)';
      }
      return priceMinor == null
          ? DiscountMath.validateGeneral(kind, value)
          : DiscountMath.validateForPrice(kind, value, priceMinor);
    };
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final value = parseDiscountValue(kind, valueController.text);
    final price = priceMinor;
    final valid = value != null &&
        (price == null
            ? DiscountMath.validateGeneral(kind, value) == null
            : DiscountMath.validateForPrice(kind, value, price) == null);
    final amount =
        (valid && value != null && price != null) ? DiscountMath.amount(kind, value, price) : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<DiscountKind>(
          segments: const [
            ButtonSegment(value: DiscountKind.percent, label: Text('Percentage')),
            ButtonSegment(value: DiscountKind.fixed, label: Text('Fixed amount')),
          ],
          selected: {kind},
          onSelectionChanged: enabled ? (s) => onKindChanged(s.first) : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: valueController,
          enabled: enabled,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: kind == DiscountKind.percent ? 'Discount (%)' : 'Discount amount',
            prefixText: kind == DiscountKind.fixed ? '\u09F3 ' : null,
            suffixText: kind == DiscountKind.percent ? '%' : null,
          ),
          onChanged: (_) => onChanged?.call(),
          validator: enabled ? validator(kind, price) : null,
        ),
        if (price != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.burgundy.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _line(textTheme, 'Original price', formatMoney(price)),
                _line(textTheme, 'Discount amount',
                    enabled && valid ? '-${formatMoney(amount)}' : '-'),
                const Divider(height: 16),
                _line(
                  textTheme,
                  'Resulting price',
                  enabled && valid ? formatMoney(price - amount) : formatMoney(price),
                  bold: true,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _line(TextTheme t, String label, String value, {bool bold = false}) {
    final style = t.bodyMedium?.copyWith(fontWeight: bold ? FontWeight.w800 : FontWeight.w400);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}
