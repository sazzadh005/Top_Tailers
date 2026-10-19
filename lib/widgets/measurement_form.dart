import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/measurements.dart';

/// Owns one text controller per measurement field.
class MeasurementControllers {
  MeasurementControllers([BodyMeasurements initial = BodyMeasurements.empty])
      : _controllers = {
          for (final f in MeasurementField.values)
            f: TextEditingController(
              text: initial[f] == null ? '' : BodyMeasurements.toText(initial[f]!),
            ),
        };

  final Map<MeasurementField, TextEditingController> _controllers;

  TextEditingController operator [](MeasurementField f) => _controllers[f]!;

  BodyMeasurements toMeasurements() => BodyMeasurements.fromText({
        for (final f in MeasurementField.values) f: _controllers[f]!.text,
      });

  void setAll(BodyMeasurements m) {
    for (final f in MeasurementField.values) {
      _controllers[f]!.text = m[f] == null ? '' : BodyMeasurements.toText(m[f]!);
    }
  }

  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
  }
}

/// All measurement inputs in centimetres, with "how to measure" guidance.
/// Fields are optional; only the ones a garment needs have to be filled in.
class MeasurementFormSection extends StatelessWidget {
  const MeasurementFormSection({
    super.key,
    required this.controllers,
    this.enabled = true,
  });

  final MeasurementControllers controllers;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'All values in centimetres (cm). Leave blank anything you do not need.',
          style: textTheme.bodySmall?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 8),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            title: Text('How to measure',
                style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.burgundy, fontWeight: FontWeight.w700)),
            leading: const Icon(Icons.straighten, color: AppColors.burgundy),
            children: [
              for (final f in MeasurementField.values)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text('${f.label}: ${f.hint}', style: textTheme.bodySmall),
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                'Use a soft tape, keep it snug but not tight, and measure over light clothing.',
                style: textTheme.bodySmall?.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth >= 320;
            final width = twoColumns ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final f in MeasurementField.values)
                  SizedBox(
                    width: width,
                    child: TextFormField(
                      controller: controllers[f],
                      enabled: enabled,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: f.label,
                        suffixText: 'cm',
                        isDense: true,
                      ),
                      validator: f.validate,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Read-only list of measurements.
class MeasurementSummary extends StatelessWidget {
  const MeasurementSummary({super.key, required this.measurements});

  final BodyMeasurements measurements;

  @override
  Widget build(BuildContext context) {
    if (measurements.isEmpty) {
      return Text('No measurements saved.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted));
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final f in MeasurementField.values)
          if (measurements[f] != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.burgundy.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${f.label}: ${BodyMeasurements.toText(measurements[f]!)} cm',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
      ],
    );
  }
}
