import 'measurements.dart';

enum UserRole { customer, admin }

/// Mirrors the `users` collection in the SRS (name, email, phone, address,
/// profileImage, role, createdAt) plus saved body measurements.
///
/// This is the *editable profile*. Orders keep their own snapshots of the
/// contact number, address and measurements.
class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.address,
    required this.role,
    required this.createdAt,
    this.profileImage,
    this.measurements = BodyMeasurements.empty,
  });

  final String id;
  final String name;
  final String email;
  final String phone;
  final String address;
  final String? profileImage;
  final UserRole role;
  final DateTime createdAt;
  final BodyMeasurements measurements;

  bool get isAdmin => role == UserRole.admin;

  String get initials {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  AppUser copyWith({
    String? name,
    String? phone,
    String? address,
    String? profileImage,
    bool clearProfileImage = false,
    BodyMeasurements? measurements,
  }) {
    return AppUser(
      id: id,
      name: name ?? this.name,
      email: email,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      profileImage: clearProfileImage ? null : (profileImage ?? this.profileImage),
      role: role,
      createdAt: createdAt,
      measurements: measurements ?? this.measurements,
    );
  }
}
