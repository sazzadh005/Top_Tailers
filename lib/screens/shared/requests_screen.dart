import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_exception.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/product.dart';
import '../../models/requests.dart';
import '../../providers/auth_provider.dart';
import '../../providers/catalog_provider.dart';
import '../../providers/load_state.dart';
import '../../providers/requests_provider.dart';
import '../../widgets/common.dart';

/// Customer "Suggestions & restock requests". Kept separate from product
/// feedback, cancellation reasons and order complaints.
class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key});

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = context.read<AuthProvider>().user;
      if (user != null) context.read<RequestsProvider>().loadMine(user.id);
    });
  }

  Future<void> _openSuggestionForm() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _SuggestionForm(),
    );
  }

  Future<void> _openRestockForm() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _RestockForm(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RequestsProvider>();

    Widget list<T>(List<T> items, Widget Function(T) tile, String emptyTitle, String emptyMsg) {
      if (provider.state == LoadState.loading && items.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      if (items.isEmpty) {
        return EmptyState(
          icon: Icons.lightbulb_outline,
          title: emptyTitle,
          message: emptyMsg,
        );
      }
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        itemCount: items.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) => tile(items[index]),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Builder(
        builder: (context) {
          final tabs = DefaultTabController.of(context);
          return Scaffold(
            appBar: AppBar(
              title: const Text('Suggestions & requests'),
              bottom: const TabBar(
                labelColor: AppColors.burgundy,
                indicatorColor: AppColors.burgundy,
                tabs: [Tab(text: 'New ideas'), Tab(text: 'Restock')],
              ),
            ),
            body: TabBarView(
              children: [
                list<ProductSuggestion>(
                  provider.suggestions,
                  (s) => _RequestCard(
                    title: s.title,
                    body: s.details,
                    status: s.status,
                    date: s.createdAt,
                  ),
                  'No suggestions yet',
                  'Tell us which fabric or product you would like the shop to stock.',
                ),
                list<RestockRequest>(
                  provider.restocks,
                  (r) => _RequestCard(
                    title: '${r.productName} (${r.productCode})',
                    body: r.reason,
                    status: r.status,
                    date: r.createdAt,
                  ),
                  'No restock requests yet',
                  'Ask us to bring back a product that is out of stock.',
                ),
              ],
            ),
            floatingActionButton: AnimatedBuilder(
              animation: tabs,
              builder: (context, child) {
                final isIdeas = tabs.index == 0;
                return FloatingActionButton.extended(
                  onPressed: isIdeas ? _openSuggestionForm : _openRestockForm,
                  icon: const Icon(Icons.add),
                  label: Text(isIdeas ? 'Suggest a product' : 'Request restock'),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.title,
    required this.body,
    required this.status,
    required this.date,
  });

  final String title;
  final String body;
  final RequestStatus status;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 8),
                Pill(label: status.label, color: requestStatusColor(status)),
              ],
            ),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(body),
            ],
            const SizedBox(height: 6),
            Text(formatShortDate(date),
                style: textTheme.bodySmall?.copyWith(color: AppColors.muted)),
          ],
        ),
      ),
    );
  }
}

class _SuggestionForm extends StatefulWidget {
  const _SuggestionForm();

  @override
  State<_SuggestionForm> createState() => _SuggestionFormState();
}

class _SuggestionFormState extends State<_SuggestionForm> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _details = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final user = context.read<AuthProvider>().user;
    final requests = context.read<RequestsProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (user == null) return;
    setState(() => _busy = true);
    try {
      await requests.submitSuggestion(
        ProductSuggestion(
          id: '',
          userId: user.id,
          userName: user.name,
          title: _title.text,
          details: _details.text,
          createdAt: DateTime.now(),
        ),
      );
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Suggestion sent. Thank you!')),
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
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Suggest a new product',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              TextFormField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'What should we stock?'),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return 'Please enter a product or fabric name';
                  if (t.length < 3) return 'Please enter at least 3 characters';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _details,
                maxLines: 4,
                maxLength: 400,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Details (colour, use, why)',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 8),
              PrimaryButton(label: 'Send suggestion', busy: _busy, onPressed: _submit),
            ],
          ),
        ),
      ),
    );
  }
}

class _RestockForm extends StatefulWidget {
  const _RestockForm();

  @override
  State<_RestockForm> createState() => _RestockFormState();
}

class _RestockFormState extends State<_RestockForm> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();
  List<Product> _products = [];
  Product? _selected;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final catalog = context.read<CatalogProvider>();
    try {
      final list = await catalog.fetchPickerProducts();
      // Unavailable products first: they are the likeliest restock targets.
      list.sort((a, b) {
        if (a.availability != b.availability) return a.availability ? 1 : -1;
        return a.productName.compareTo(b.productName);
      });
      if (mounted) setState(() => _products = list);
    } catch (_) {
      // Leave the list empty; the empty state explains it.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final user = context.read<AuthProvider>().user;
    final requests = context.read<RequestsProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final product = _selected;
    if (user == null || product == null) return;
    setState(() => _busy = true);
    try {
      await requests.submitRestock(
        RestockRequest(
          id: '',
          userId: user.id,
          userName: user.name,
          productId: product.id,
          productCode: product.code,
          productName: product.productName,
          reason: _reason.text,
          createdAt: DateTime.now(),
        ),
      );
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Restock request sent. Thank you!')),
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
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Request a restock',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                DropdownButtonFormField<Product>(
                  initialValue: _selected,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Product'),
                  items: [
                    for (final p in _products)
                      DropdownMenuItem<Product>(
                        value: p,
                        child: Text(
                          '${p.productName} (${p.code})${p.availability ? '' : ' - out of stock'}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _selected = v),
                  validator: (v) => v == null ? 'Please choose a product' : null,
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _reason,
                maxLines: 3,
                maxLength: 300,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Why do you need it? (optional)',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 8),
              PrimaryButton(label: 'Send request', busy: _busy, onPressed: _submit),
            ],
          ),
        ),
      ),
    );
  }
}
