/// Body measurement fields offered for tailoring. Values are in centimetres.
enum MeasurementField {
  neck,
  chest,
  shoulder,
  sleeveLength,
  armhole,
  waist,
  hip,
  shirtLength,
  trouserWaist,
  inseam,
  trouserLength,
}

extension MeasurementFieldX on MeasurementField {
  String get label {
    switch (this) {
      case MeasurementField.neck:
        return 'Neck';
      case MeasurementField.chest:
        return 'Chest';
      case MeasurementField.shoulder:
        return 'Shoulder';
      case MeasurementField.sleeveLength:
        return 'Sleeve length';
      case MeasurementField.armhole:
        return 'Armhole';
      case MeasurementField.waist:
        return 'Waist';
      case MeasurementField.hip:
        return 'Hip';
      case MeasurementField.shirtLength:
        return 'Shirt length';
      case MeasurementField.trouserWaist:
        return 'Trouser waist';
      case MeasurementField.inseam:
        return 'Inseam';
      case MeasurementField.trouserLength:
        return 'Trouser length';
    }
  }

  /// Short "how to measure" guidance.
  String get hint {
    switch (this) {
      case MeasurementField.neck:
        return 'Around the base of the neck';
      case MeasurementField.chest:
        return 'Around the fullest part of the chest';
      case MeasurementField.shoulder:
        return 'Across the back, shoulder point to shoulder point';
      case MeasurementField.sleeveLength:
        return 'Shoulder point to the wrist, arm slightly bent';
      case MeasurementField.armhole:
        return 'Around the top of the arm where the sleeve joins';
      case MeasurementField.waist:
        return 'Around the natural waistline';
      case MeasurementField.hip:
        return 'Around the fullest part of the hips';
      case MeasurementField.shirtLength:
        return 'Base of the neck to the desired hem';
      case MeasurementField.trouserWaist:
        return 'Where the trousers will sit';
      case MeasurementField.inseam:
        return 'Crotch to the ankle along the inner leg';
      case MeasurementField.trouserLength:
        return 'Waist to the ankle along the outer leg';
    }
  }

  /// Plausible range in cm. These are sanity limits for typo detection, not
  /// business rules.
  double get minCm {
    switch (this) {
      case MeasurementField.neck:
        return 25;
      case MeasurementField.chest:
      case MeasurementField.hip:
        return 60;
      case MeasurementField.shoulder:
      case MeasurementField.armhole:
        return 30;
      case MeasurementField.sleeveLength:
      case MeasurementField.shirtLength:
        return 40;
      case MeasurementField.waist:
      case MeasurementField.trouserWaist:
      case MeasurementField.inseam:
        return 50;
      case MeasurementField.trouserLength:
        return 70;
    }
  }

  double get maxCm {
    switch (this) {
      case MeasurementField.neck:
        return 60;
      case MeasurementField.chest:
        return 160;
      case MeasurementField.shoulder:
        return 70;
      case MeasurementField.sleeveLength:
        return 90;
      case MeasurementField.armhole:
        return 80;
      case MeasurementField.waist:
      case MeasurementField.trouserWaist:
        return 160;
      case MeasurementField.hip:
        return 180;
      case MeasurementField.shirtLength:
      case MeasurementField.inseam:
        return 110;
      case MeasurementField.trouserLength:
        return 140;
    }
  }

  /// Validates optional text input; null means valid (blank is allowed).
  String? validate(String? text) {
    final t = (text ?? '').trim();
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    if (v == null) return 'Enter a number';
    if (v < minCm || v > maxCm) {
      return '${minCm.toStringAsFixed(0)}-${maxCm.toStringAsFixed(0)} cm';
    }
    return null;
  }
}

/// A set of body measurements in centimetres. Every field is optional.
class BodyMeasurements {
  const BodyMeasurements([this.values = const {}]);

  final Map<MeasurementField, double> values;

  static const BodyMeasurements empty = BodyMeasurements();

  bool get isEmpty => values.isEmpty;
  bool get isNotEmpty => values.isNotEmpty;
  double? operator [](MeasurementField f) => values[f];

  /// Builds from raw text input, ignoring blank or invalid entries.
  factory BodyMeasurements.fromText(Map<MeasurementField, String> input) {
    final map = <MeasurementField, double>{};
    input.forEach((field, text) {
      final v = double.tryParse(text.trim());
      if (v != null) map[field] = v;
    });
    return BodyMeasurements(map);
  }

  /// Field-by-field text for editing: 90.0 -> "90", 90.5 -> "90.5".
  static String toText(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
}

/// Where an order's measurements came from.
enum MeasurementSource { profile, enteredForOrder, otherPerson }

extension MeasurementSourceX on MeasurementSource {
  String get label {
    switch (this) {
      case MeasurementSource.profile:
        return 'Saved profile measurements';
      case MeasurementSource.enteredForOrder:
        return 'Entered for this order';
      case MeasurementSource.otherPerson:
        return 'Measurements for another person';
    }
  }
}

/// Immutable copy of the measurements used for one order. Editing the
/// customer's profile later never changes it.
class OrderMeasurementSnapshot {
  const OrderMeasurementSnapshot({
    required this.measurements,
    required this.source,
    this.forPerson,
    required this.capturedAt,
  });

  final BodyMeasurements measurements;
  final MeasurementSource source;

  /// Name of the person measured when [source] is otherPerson.
  final String? forPerson;
  final DateTime capturedAt;
}
