import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Displays a remote image or a locally selected image.
class AppImage extends StatelessWidget {
  const AppImage({
    super.key,
    required this.source,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.fallback,
  });

  final Object source;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? fallback;

  static bool isRemote(String value) =>
      value.startsWith('http://') || value.startsWith('https://');

  @override
  Widget build(BuildContext context) {
    final fb = fallback ?? const SizedBox.shrink();

    if (source is XFile) {
      return FutureBuilder(
        future: (source as XFile).readAsBytes(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return fb;

          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          }

          return Image.memory(
            snapshot.data!,
            fit: fit,
            width: width,
            height: height,
            errorBuilder: (context, error, stackTrace) => fb,
          );
        },
      );
    }

    if (source is String && isRemote(source as String)) {
      return Image.network(
        source as String,
        fit: fit,
        width: width,
        height: height,
        errorBuilder: (context, error, stackTrace) => fb,
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : const Center(
                child: SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
      );
    }

    return fb;
  }
}