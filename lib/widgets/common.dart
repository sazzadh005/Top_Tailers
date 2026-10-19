import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/theme.dart';
import '../models/order.dart';
import '../models/payment.dart';
import '../models/requests.dart';

/// Shows a floating snackbar. Use [error] for failures.
void showAppSnack(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.danger : AppColors.ink,
      ),
    );
}

/// Asks the user to confirm a (usually destructive) action.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(cancelLabel),
        ),
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: destructive ? AppColors.danger : AppColors.burgundy,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Opens the gallery and returns the picked image path, or null.
/// Enforces a 5 MB upload limit (SRS: upload limits are set).
Future<String?> pickImagePath(BuildContext context) async {
  try {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 80,
    );
    if (picked == null) return null;
    final size = await File(picked.path).length();
    if (size > 5 * 1024 * 1024) {
      if (context.mounted) {
        showAppSnack(context, 'Image is too large. Please choose one under 5 MB.',
            error: true);
      }
      return null;
    }
    return picked.path;
  } catch (_) {
    if (context.mounted) {
      showAppSnack(context, 'Could not open the gallery.', error: true);
    }
    return null;
  }
}

/// Filled button that shows a spinner and ignores taps while [busy].
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final child = busy
        ? const SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            ],
          );
    return ElevatedButton(
      onPressed: busy ? null : onPressed,
      child: child,
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: AppColors.burgundy.withValues(alpha: 0.08),
              child: Icon(icon, size: 40, color: AppColors.burgundy),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.muted),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: 220,
                child: ElevatedButton(onPressed: onAction, child: Text(actionLabel!)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.cloud_off_outlined,
      title: 'Something went wrong',
      message: message,
      actionLabel: 'Try again',
      onAction: onRetry,
    );
  }
}

/// Section title with an optional trailing action ("See all").
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

/// Horizontal single-select chips (categories, order status filters).
class FilterChips extends StatelessWidget {
  const FilterChips({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: labels.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final selected = index == selectedIndex;
          return ChoiceChip(
            label: Text(labels[index]),
            selected: selected,
            showCheckmark: false,
            selectedColor: AppColors.burgundy,
            backgroundColor: Colors.white,
            side: const BorderSide(color: AppColors.border),
            labelStyle: TextStyle(
              color: selected ? Colors.white : AppColors.ink,
              fontWeight: FontWeight.w600,
            ),
            onSelected: (_) => onSelected(index),
          );
        },
      ),
    );
  }
}

Color statusColor(OrderStatus status) {
  switch (status) {
    case OrderStatus.pending:
      return AppColors.warning;
    case OrderStatus.confirmed:
      return AppColors.info;
    case OrderStatus.processing:
      return AppColors.burgundy;
    case OrderStatus.completed:
      return AppColors.success;
    case OrderStatus.cancelled:
      return AppColors.danger;
  }
}

Color paymentColor(PaymentStatus status) {
  switch (status) {
    case PaymentStatus.pending:
      return AppColors.warning;
    case PaymentStatus.successful:
      return AppColors.success;
    case PaymentStatus.failed:
      return AppColors.danger;
    case PaymentStatus.cancelled:
      return AppColors.muted;
  }
}

Color requestStatusColor(RequestStatus status) {
  switch (status) {
    case RequestStatus.received:
      return AppColors.info;
    case RequestStatus.underReview:
      return AppColors.warning;
    case RequestStatus.planned:
      return AppColors.success;
    case RequestStatus.declined:
      return AppColors.danger;
  }
}

/// Small coloured pill used for statuses.
class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 4)],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// Order (fulfilment) status chip.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) =>
      Pill(label: status.label, color: statusColor(status));
}

/// Payment status chip, kept separate from the order status.
class PaymentChip extends StatelessWidget {
  const PaymentChip({super.key, required this.payment});

  final PaymentRecord payment;

  @override
  Widget build(BuildContext context) => Pill(
        label: payment.statusLabel,
        color: paymentColor(payment.status),
        icon: payment.method == PaymentMethod.cod
            ? Icons.payments_outlined
            : Icons.credit_card,
      );
}

/// Small label/value row used in detail screens.
class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.burgundy),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.muted)),
                const SizedBox(height: 2),
                Text(value, style: Theme.of(context).textTheme.bodyLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Brand mark used on splash and auth screens.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 84, this.onDark = false});

  final double size;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: onDark ? AppColors.gold : AppColors.burgundy,
      ),
      child: Icon(
        Icons.content_cut,
        size: size * 0.5,
        color: onDark ? AppColors.burgundyDark : Colors.white,
      ),
    );
  }
}

/// Pulsing grey placeholder shown while content loads.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({super.key, this.height, this.width, this.radius = 12});

  final double? height;
  final double? width;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            color: Color.lerp(const Color(0xFFEDE6DA), const Color(0xFFE2D9CA), _controller.value),
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        );
      },
    );
  }
}

/// Read-only star display.
class StarRating extends StatelessWidget {
  const StarRating({super.key, required this.rating, this.size = 16});

  final double rating;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            rating >= i
                ? Icons.star
                : (rating >= i - 0.5 ? Icons.star_half : Icons.star_border),
            size: size,
            color: AppColors.gold,
          ),
      ],
    );
  }
}

/// Tappable 1-5 star input.
class StarPicker extends StatelessWidget {
  const StarPicker({super.key, required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          IconButton(
            tooltip: '$i star${i == 1 ? '' : 's'}',
            onPressed: () => onChanged(i),
            iconSize: 34,
            icon: Icon(
              value >= i ? Icons.star : Icons.star_border,
              color: AppColors.gold,
            ),
          ),
      ],
    );
  }
}

/// Banner reminding users that a flow is a demonstration.
class DemoNotice extends StatelessWidget {
  const DemoNotice({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.science_outlined, size: 20, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// Single-choice row (radio look) built from stable widgets.
class ChoiceTile<T> extends StatelessWidget {
  const ChoiceTile({
    super.key,
    required this.value,
    required this.groupValue,
    required this.title,
    required this.onChanged,
    this.subtitle,
    this.enabled = true,
  });

  final T value;
  final T? groupValue;
  final String title;
  final String? subtitle;
  final bool enabled;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: enabled,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: !enabled
            ? AppColors.border
            : (selected ? AppColors.burgundy : AppColors.muted),
      ),
      title: Text(title, style: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
      subtitle: subtitle == null ? null : Text(subtitle!),
      onTap: enabled ? () => onChanged(value) : null,
    );
  }
}
