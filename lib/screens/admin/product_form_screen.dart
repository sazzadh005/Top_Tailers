import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_exception.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../core/validators.dart';
import '../../domain/discount.dart';
import '../../models/product.dart';
import '../../providers/catalog_provider.dart';
import '../../widgets/common.dart';
import '../../widgets/discount_editor.dart';

/// Known colour names -> ARGB, so admins can type "Navy, Maroon" and get
/// sensible swatches. Unknown names get a neutral grey.
const Map<String, int> _knownColors = {
  'white': 0xFFF4F1EA,
  'black': 0xFF1E1E1E,
  'navy': 0xFF1E2D52,
  'maroon': 0xFF7B1E3A,
  'sky blue': 0xFF9CC3E4,
  'light blue': 0xFFB9D3EA,
  'blue': 0xFF2F5DA8,
  'red': 0xFFB3262E,
  'green': 0xFF2F6B4F,
  'emerald': 0xFF1F7A5C,
  'olive': 0xFF6B6F3A,
  'grey': 0xFF8A8D91,
  'charcoal': 0xFF3D3F44,
  'cream': 0xFFF1E7CF,
  'ivory': 0xFFEFE6D2,
  'sand': 0xFFD8C3A0,
  'gold': 0xFFC9A24B,
  'wine': 0xFF5B1730,
  'pink': 0xFFE4A0B5,
  'yellow': 0xFFE3C84A,
  'brown': 0xFF6B4A32,
};

/// Add a new product, or edit [product] when it is provided.
class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({super.key, this.product});

  final Product? product;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _code;
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _price;
  late final TextEditingController _colors;
  late final TextEditingController _sizes;
  late final TextEditingController _material;
  late final TextEditingController _width;
  late final TextEditingController _care;
  late final TextEditingController _discountValue;
  late String _category;
  late bool _availability;
  late bool _featured;
  late bool _requiresMeasurements;
  late bool _discountEnabled;
  late DiscountKind _discountKind;
  late List<String> _images;
  bool _busy = false;
  String? _codeError;

  bool get _isEditing => widget.product != null;

  static String _unitFor(String category) {
    switch (category) {
      case 'Fabrics':
        return 'yard';
      case 'Tailoring':
        return 'service';
      default:
        return 'piece';
    }
  }

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _code = TextEditingController(text: p?.code ?? '');
    _name = TextEditingController(text: p?.productName ?? '');
    _description = TextEditingController(text: p?.description ?? '');
    _price = TextEditingController(text: p == null ? '' : Money.toInput(p.priceMinor));
    _colors = TextEditingController(text: p?.colors.map((c) => c.name).join(', ') ?? '');
    _sizes = TextEditingController(text: p?.sizes.join(', ') ?? '');
    _material = TextEditingController(text: p?.specs['Material'] ?? '');
    _width = TextEditingController(text: p?.specs['Width'] ?? '');
    _care = TextEditingController(text: p?.specs['Care'] ?? '');
    _category = (p != null && kCategories.contains(p.category)) ? p.category : kCategories.first;
    _availability = p?.availability ?? true;
    _featured = p?.isFeatured ?? false;
    _requiresMeasurements = p?.requiresMeasurements ?? false;
    _images = List<String>.of(p?.imagePaths ?? const []);
    final d = p?.discount;
    _discountEnabled = d?.enabled ?? false;
    _discountKind = d?.kind ?? DiscountKind.percent;
    _discountValue = TextEditingController(
      text: d == null
          ? ''
          : (d.kind == DiscountKind.percent ? '${d.value}' : Money.toInput(d.value)),
    );
  }

  @override
  void dispose() {
    for (final c in [
      _code, _name, _description, _price, _colors, _sizes,
      _material, _width, _care, _discountValue,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> _split(String text) => text
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  Future<void> _addImage() async {
    if (_images.length >= 4) {
      showAppSnack(context, 'You can add up to 4 images.', error: true);
      return;
    }
    final path = await pickImagePath(context);
    if (path != null && mounted) setState(() => _images.add(path));
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    final catalog = context.read<CatalogProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final price = Money.tryParse(_price.text)!;
    final code = _code.text.trim().toUpperCase();

    // Duplicate check with an inline message. The repository enforces it too.
    try {
      final taken = await catalog.isCodeTaken(code, exceptProductId: widget.product?.id);
      if (!mounted) return;
      if (taken) {
        setState(() => _codeError = 'Code $code is already used by another product');
        _formKey.currentState!.validate();
        return;
      }
    } catch (e) {
      if (mounted) showAppSnack(context, errorText(e), error: true);
      return;
    }

    ProductDiscount? discount;
    if (_discountEnabled) {
      discount = ProductDiscount(
        enabled: true,
        kind: _discountKind,
        value: parseDiscountValue(_discountKind, _discountValue.text)!,
      );
    } else if (_discountValue.text.trim().isNotEmpty) {
      // Keep a disabled discount's settings so it can be switched back on.
      final v = parseDiscountValue(_discountKind, _discountValue.text);
      if (v != null) {
        discount = ProductDiscount(enabled: false, kind: _discountKind, value: v);
      }
    }

    final specs = <String, String>{
      if (_material.text.trim().isNotEmpty) 'Material': _material.text.trim(),
      if (_width.text.trim().isNotEmpty) 'Width': _width.text.trim(),
      if (_care.text.trim().isNotEmpty) 'Care': _care.text.trim(),
    };
    final colors = [
      for (final name in _split(_colors.text))
        FabricColor(name: name, argb: _knownColors[name.toLowerCase()] ?? 0xFF9E9E9E),
    ];

    final existing = widget.product;
    final draft = Product(
      id: existing?.id ?? '',
      code: code,
      productName: _name.text.trim(),
      description: _description.text.trim(),
      priceMinor: price,
      category: _category,
      availability: _availability,
      imagePaths: _images,
      colors: colors,
      sizes: _category == 'Readymade' ? _split(_sizes.text) : const [],
      specs: specs,
      isFeatured: _featured,
      popularity: existing?.popularity ?? 0,
      unit: _unitFor(_category),
      requiresMeasurements: _requiresMeasurements,
      discount: discount,
      createdAt: existing?.createdAt ?? DateTime.now(),
    );

    setState(() => _busy = true);
    try {
      if (existing == null) {
        await catalog.createProduct(draft);
      } else {
        await catalog.updateProduct(draft);
      }
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text(existing == null ? 'Product added' : 'Product updated')),
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
    final textTheme = Theme.of(context).textTheme;
    final priceMinor = Money.tryParse(_price.text);

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit Product' : 'Add Product')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Images (up to 4)',
                  style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              SizedBox(
                height: 92,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (var i = 0; i < _images.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(
                                File(_images[i]),
                                height: 92,
                                width: 92,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stack) => Container(
                                  height: 92,
                                  width: 92,
                                  color: AppColors.border,
                                  child: const Icon(Icons.broken_image_outlined),
                                ),
                              ),
                            ),
                            Positioned(
                              right: 2,
                              top: 2,
                              child: InkWell(
                                onTap: () => setState(() => _images.removeAt(i)),
                                child: const CircleAvatar(
                                  radius: 12,
                                  backgroundColor: AppColors.danger,
                                  child: Icon(Icons.close, size: 14, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    InkWell(
                      onTap: _addImage,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        height: 92,
                        width: 92,
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.white,
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_a_photo_outlined, color: AppColors.burgundy),
                            SizedBox(height: 4),
                            Text('Add', style: TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'JPG or PNG, up to 5 MB each. A fabric swatch is shown when no image is set.',
                style: textTheme.bodySmall?.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Product code',
                  helperText: 'Unique and permanent, e.g. FAB-COT-001',
                ),
                onChanged: (_) {
                  if (_codeError != null) setState(() => _codeError = null);
                },
                validator: (v) => _codeError ?? Validators.productCode(v),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Product name'),
                validator: (v) => Validators.required(v, 'Product name'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _description,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  alignLabelWithHint: true,
                ),
                validator: (v) => Validators.required(v, 'Description'),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: InputDecoration(
                  labelText: 'Category',
                  helperText: 'Sold per ${_unitFor(_category)}',
                ),
                items: [
                  for (final c in kCategories)
                    DropdownMenuItem<String>(value: c, child: Text(c)),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _category = v;
                    if (v == 'Tailoring') _requiresMeasurements = true;
                  });
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Price per ${_unitFor(_category)}',
                  prefixText: '\u09F3 ',
                ),
                onChanged: (_) => setState(() {}),
                validator: Validators.price,
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        activeThumbColor: AppColors.burgundy,
                        title: const Text('Product discount',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: const Text('Shown on cards, details, cart and orders'),
                        value: _discountEnabled,
                        onChanged: (v) => setState(() => _discountEnabled = v),
                      ),
                      if (_discountEnabled) ...[
                        const SizedBox(height: 8),
                        DiscountEditor(
                          kind: _discountKind,
                          valueController: _discountValue,
                          priceMinor: priceMinor,
                          onKindChanged: (k) => setState(() {
                            _discountKind = k;
                            _discountValue.clear();
                          }),
                          onChanged: () => setState(() {}),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Vouchers and customer discounts do not apply to discounted items.',
                          style: textTheme.bodySmall?.copyWith(color: AppColors.muted),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _colors,
                decoration: const InputDecoration(
                  labelText: 'Colours (optional, comma separated)',
                  hintText: 'White, Navy, Maroon',
                ),
              ),
              if (_category == 'Readymade') ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _sizes,
                  decoration: const InputDecoration(
                    labelText: 'Sizes (comma separated)',
                    hintText: 'S, M, L, XL',
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (_category == 'Fabrics') ...[
                TextFormField(
                  controller: _material,
                  decoration: const InputDecoration(labelText: 'Material (optional)'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _width,
                  decoration: const InputDecoration(labelText: 'Width (optional)'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _care,
                  decoration: const InputDecoration(labelText: 'Care instructions (optional)'),
                ),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: AppColors.burgundy,
                title: const Text('Available for purchase'),
                subtitle: Text(_availability
                    ? 'Customers can add this to their cart'
                    : 'Shown as out of stock'),
                value: _availability,
                onChanged: (v) => setState(() => _availability = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: AppColors.burgundy,
                title: const Text('Featured on home'),
                value: _featured,
                onChanged: (v) => setState(() => _featured = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: AppColors.burgundy,
                title: const Text('Needs body measurements'),
                subtitle: const Text('Customers provide measurements at checkout'),
                value: _requiresMeasurements,
                onChanged: (v) => setState(() => _requiresMeasurements = v),
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: _isEditing ? 'Save Changes' : 'Add Product',
                busy: _busy,
                onPressed: _save,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
