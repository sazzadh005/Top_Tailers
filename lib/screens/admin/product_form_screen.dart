import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_exception.dart';
import '../../core/theme.dart';
import '../../core/validators.dart';
import '../../models/product.dart';
import '../../providers/catalog_provider.dart';
import '../../widgets/common.dart';

/// Add a new product, or edit [product] when it is provided.
class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({super.key, this.product});

  final Product? product;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _price;
  late String _category;
  late bool _availability;
  String? _imagePath;
  bool _busy = false;

  bool get _isEditing => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _name = TextEditingController(text: p?.productName ?? '');
    _description = TextEditingController(text: p?.description ?? '');
    _price = TextEditingController(
      text: p == null
          ? ''
          : (p.price == p.price.roundToDouble()
              ? p.price.toStringAsFixed(0)
              : p.price.toString()),
    );
    _category = (p != null && kCategories.contains(p.category))
        ? p.category
        : kCategories.first;
    _availability = p?.availability ?? true;
    _imagePath = p?.imagePath;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final path = await pickImagePath(context);
    if (path != null && mounted) setState(() => _imagePath = path);
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    final catalog = context.read<CatalogProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final existing = widget.product;
    final product = Product(
      id: existing?.id ?? '',
      productName: _name.text.trim(),
      description: _description.text.trim(),
      price: double.parse(_price.text.trim()),
      category: _category,
      availability: _availability,
      imagePath: _imagePath,
    );

    setState(() => _busy = true);
    try {
      if (existing == null) {
        await catalog.addProduct(product);
      } else {
        await catalog.updateProduct(product);
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
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit Product' : 'Add Product')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 1.7,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ProductImage(
                        category: _category,
                        imagePath: _imagePath,
                        borderRadius: 14,
                        iconSize: 56,
                      ),
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.burgundy,
                            minimumSize: const Size(48, 44),
                          ),
                          onPressed: _pickImage,
                          icon: const Icon(Icons.photo_camera_outlined, size: 20),
                          label: Text(_imagePath == null ? 'Upload image' : 'Change'),
                        ),
                      ),
                      if (_imagePath != null)
                        Positioned(
                          left: 8,
                          bottom: 8,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.danger,
                              minimumSize: const Size(48, 44),
                            ),
                            onPressed: () => setState(() => _imagePath = null),
                            icon: const Icon(Icons.delete_outline, size: 20),
                            label: const Text('Remove'),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'JPG or PNG, up to 5 MB. A category placeholder is shown when no image is set.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.muted),
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
                TextFormField(
                  controller: _price,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Price',
                    prefixText: '৳ ',
                  ),
                  validator: Validators.price,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    for (final c in kCategories)
                      DropdownMenuItem<String>(value: c, child: Text(c)),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _category = v);
                  },
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: AppColors.burgundy,
                  title: const Text('Available for purchase'),
                  subtitle: Text(
                    _availability
                        ? 'Customers can add this to their cart'
                        : 'Shown as out of stock',
                  ),
                  value: _availability,
                  onChanged: (v) => setState(() => _availability = v),
                ),
                const SizedBox(height: 16),
                PrimaryButton(
                  label: _isEditing ? 'Save Changes' : 'Add Product',
                  busy: _busy,
                  onPressed: _save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
