import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_exception.dart';
import '../../core/format.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../domain/discount.dart';
import '../../models/customer_discount.dart';
import '../../models/product.dart';
import '../../providers/catalog_provider.dart';
import '../../providers/customers_provider.dart';
import '../../widgets/common.dart';
import '../../widgets/discount_editor.dart';
import '../../widgets/product_widgets.dart';
import 'customer_discount_sheet.dart';

String describeDiscount(DiscountKind kind, int value) =>
    kind == DiscountKind.percent ? '$value% off' : '${formatMoney(value)} off';

/// Admin discount management: product discounts and customer-specific
/// discounts, kept separate from vouchers.
class DiscountsScreen extends StatelessWidget {
  const DiscountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Discounts'),
          bottom: const TabBar(
            labelColor: AppColors.burgundy,
            indicatorColor: AppColors.burgundy,
            tabs: [Tab(text: 'Products'), Tab(text: 'Customers')],
          ),
        ),
        body: const TabBarView(children: [_ProductDiscounts(), _CustomerDiscounts()]),
      ),
    );
  }
}

class _ProductDiscounts extends StatefulWidget {
  const _ProductDiscounts();

  @override
  State<_ProductDiscounts> createState() => _ProductDiscountsState();
}

class _ProductDiscountsState extends State<_ProductDiscounts> {
  List<Product> _products = [];
  bool _loading = true;
  bool _discountedOnly = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final catalog = context.read<CatalogProvider>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await catalog.fetchPickerProducts();
      if (mounted) setState(() => _products = list);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit(Product product) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ProductDiscountSheet(product: product),
    );
    if (saved == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _products.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) return ErrorState(message: _error!, onRetry: _load);

    final shown = _discountedOnly ? _products.where((p) => p.hasDiscount).toList() : _products;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('All products'),
                selected: !_discountedOnly,
                onSelected: (_) => setState(() => _discountedOnly = false),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Discounted only'),
                selected: _discountedOnly,
                onSelected: (_) => setState(() => _discountedOnly = true),
              ),
            ],
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? const EmptyState(
                  icon: Icons.sell_outlined,
                  title: 'No discounted products',
                  message: 'Open any product and switch on a discount.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: shown.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final p = shown[index];
                    final d = p.discount;
                    return Card(
                      child: ListTile(
                        onTap: () => _edit(p),
                        leading: SizedBox(
                          height: 48,
                          width: 48,
                          child: ProductVisual(product: p, borderRadius: 10, iconSize: 22),
                        ),
                        title: Text(p.productName, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          p.hasDiscount
                              ? '${p.code}  |  ${formatMoney(p.priceMinor)} -> ${formatMoney(p.effectivePriceMinor)} (${describeDiscount(d!.kind, d.value)})'
                              : (d != null && !d.enabled
                                  ? '${p.code}  |  Discount off (${describeDiscount(d.kind, d.value)} saved)'
                                  : '${p.code}  |  ${formatMoney(p.priceMinor)}  |  No discount'),
                        ),
                        trailing: p.hasDiscount
                            ? const Pill(label: 'Active', color: AppColors.success)
                            : const Icon(Icons.chevron_right),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ProductDiscountSheet extends StatefulWidget {
  const _ProductDiscountSheet({required this.product});

  final Product product;

  @override
  State<_ProductDiscountSheet> createState() => _ProductDiscountSheetState();
}

class _ProductDiscountSheetState extends State<_ProductDiscountSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _value;
  late DiscountKind _kind;
  late bool _enabled;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final d = widget.product.discount;
    _enabled = d?.enabled ?? false;
    _kind = d?.kind ?? DiscountKind.percent;
    _value = TextEditingController(
      text: d == null
          ? ''
          : (d.kind == DiscountKind.percent ? '${d.value}' : Money.toInput(d.value)),
    );
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  Future<void> _save({bool remove = false}) async {
    final catalog = context.read<CatalogProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    Product updated;
    if (remove) {
      updated = widget.product.copyWith(clearDiscount: true);
    } else {
      if (_enabled && !_formKey.currentState!.validate()) return;
      final parsed = parseDiscountValue(_kind, _value.text);
      updated = widget.product.copyWith(
        discount: parsed == null
            ? null
            : ProductDiscount(enabled: _enabled, kind: _kind, value: parsed),
        clearDiscount: parsed == null,
      );
    }
    setState(() => _busy = true);
    try {
      await catalog.updateProduct(updated);
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(content: Text(remove ? 'Discount removed' : 'Discount saved')),
      );
    } catch (e) {
      if (mounted) {
        showAppSnack(context, errorText(e), error: true);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.product.productName,
                  style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              Text('Code ${widget.product.code}', style: textTheme.bodySmall),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: AppColors.burgundy,
                title: const Text('Discount enabled'),
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
              ),
              DiscountEditor(
                kind: _kind,
                valueController: _value,
                priceMinor: widget.product.priceMinor,
                enabled: _enabled,
                onKindChanged: (k) => setState(() {
                  _kind = k;
                  _value.clear();
                }),
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: 16),
              PrimaryButton(label: 'Save', busy: _busy, onPressed: () => _save()),
              if (widget.product.discount != null) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                  ),
                  onPressed: _busy ? null : () => _save(remove: true),
                  child: const Text('Remove discount'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomerDiscounts extends StatelessWidget {
  const _CustomerDiscounts();

  @override
  Widget build(BuildContext context) {
    final customers = context.watch<CustomersProvider>();
    if (customers.state == LoadState.loading && customers.customers.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (customers.customers.isEmpty) {
      return const EmptyState(
        icon: Icons.people_outline,
        title: 'No customers yet',
        message: 'Registered customers will appear here.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: customers.customers.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final c = customers.customers[index];
        final CustomerDiscount? d = customers.discountFor(c.id);
        return Card(
          child: ListTile(
            onTap: () => showCustomerDiscountSheet(context, c),
            title: Text(c.name),
            subtitle: Text(d == null
                ? 'No discount'
                : '${describeDiscount(d.kind, d.value)}${d.active ? '' : ' (inactive)'}'),
            trailing: d == null
                ? const Icon(Icons.add_circle_outline, color: AppColors.burgundy)
                : Pill(
                    label: d.active ? 'Active' : 'Inactive',
                    color: d.active ? AppColors.success : AppColors.muted,
                  ),
          ),
        );
      },
    );
  }
}
