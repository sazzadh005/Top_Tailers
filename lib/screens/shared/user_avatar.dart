import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/app_user.dart';

class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.user, this.radius = 28, this.imagePath});

  final AppUser user;
  final double radius;

  /// Overrides the saved image (used while editing, before saving).
  final String? imagePath;

  @override
  Widget build(BuildContext context) {
    final path = imagePath ?? user.profileImage;
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
      child: (path == null || path.isEmpty)
          ? fallback
          : ClipOval(
              child: Image.file(
                File(path),
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => fallback,
              ),
            ),
    );
  }
}
