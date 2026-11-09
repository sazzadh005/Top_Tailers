import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/app_user.dart';
import '../../widgets/app_image.dart';

class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.user,
    this.radius = 28,
    this.imagePath,
  });

  final AppUser user;
  final double radius;

  /// Accepts either a local XFile or a saved remote image URL.
  final Object? imagePath;

  @override
  Widget build(BuildContext context) {
    final source = imagePath ?? user.profileImage;

    final fallback = Text(
      user.initials,
      style: TextStyle(
        fontSize: radius * 0.7,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    );

    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.burgundy,
      child: source == null
          ? fallback
          : ClipOval(
              child: AppImage(
                source: source,
                width: radius * 2,
                height: radius * 2,
                fallback: fallback,
              ),
            ),
    );
  }
}