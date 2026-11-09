import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_exception.dart';
import '../../core/theme.dart';
import '../../core/validators.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common.dart';

/// Shown after the customer opens the password-reset link from their email.
class NewPasswordScreen extends StatefulWidget {
  const NewPasswordScreen({super.key});

  @override
  State<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends State<NewPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await auth.setNewPassword(_password.text);
      // The reset session is closed so the customer signs in with the new password.
      auth.logout();
      messenger.showSnackBar(const SnackBar(content: Text('Password updated. Please sign in.')));
    } catch (e) {
      if (mounted) {
        showAppSnack(context, errorText(e), error: true);
        setState(() => _busy = false);
      }
    }
  }

  void _cancel() {
    final auth = context.read<AuthProvider>();
    auth.dismissRecovery();
    auth.logout();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose a new password')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.lock_reset, size: 64, color: AppColors.burgundy),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'New password',
                        helperText: 'At least 8 characters',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      validator: (v) {
                        final base = Validators.password(v);
                        if (base != null) return base;
                        return (v ?? '').length < 8 ? 'Password must be at least 8 characters' : null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirm,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirm new password',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      validator: Validators.confirmPassword(() => _password.text),
                    ),
                    const SizedBox(height: 24),
                    PrimaryButton(label: 'Save password', busy: _busy, onPressed: _save),
                    TextButton(onPressed: _busy ? null : _cancel, child: const Text('Cancel')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
