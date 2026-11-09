/// Result of an image upload: where to display it and how to refer to it.
class UploadedImage {
  const UploadedImage({required this.url, required this.publicId});

  final String url;
  final String publicId;
}
