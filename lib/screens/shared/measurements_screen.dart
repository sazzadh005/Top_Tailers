import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_exception.dart';
import '../../models/app_user.dart';
import '../../models/measurements.dart';
import '../../providers/auth_provider.dart';
import '../../providers/customers_provider.dart';
import '../../widgets/common.dart';
import '../../widgets/measurement_form.dart';

/// View and edit saved body measurements.
///
/// With no [customer], the signed-in customer edits their own. When an admin
/// passes a [customer], the admin edits that customer's saved measurements.
/// Measurements are personal data: only the customer and the shop admin see
/// them.
class MeasurementsScreen extends StatefulWidget {
  const MeasurementsScreen({super.key, this.customer});

  final AppUser? customer;

  @override
  State<MeasurementsScreen> createState() => _MeasurementsScreenState();
}

class _MeasurementsScreenState extends State<MeasurementsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final MeasurementControllers _controllers;
  bool _busy = false;

  bool get _adminMode => widget.customer != null;

  @override
  void initState() {
    super.initState();
    final user = widget.customer ?? context.read<AuthProvider>().user;
    _controllers = MeasurementControllers(user?.measurements ?? BodyMeasurements.empty);
  }

  @override
  void dispose() {
    _controllers.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final customers = context.read<CustomersProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final measurements = _controllers.toMeasurements();
    setState(() => _busy = true);
    try {
      if (_adminMode) {
        await customers.updateMeasurements(widget.customer!.id, measurements);
      } else {
        await auth.updateMyMeasurements(measurements);
      }
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Measurements saved')));
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
      appBar: AppBar(
        title: Text(_adminMode ? '${widget.customer!.name}: measurements' : 'My measurements'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _adminMode
                      ? 'Changes here update the customer\u2019s saved profile measurements. Existing orders keep the measurements they were placed with.'
                      : 'Saved measurements are used as the default for tailoring orders. Changing them never alters orders you have already placed.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                MeasurementFormSection(controllers: _controllers),
                const SizedBox(height: 24),
                PrimaryButton(label: 'Save measurements', busy: _busy, onPressed: _save),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
