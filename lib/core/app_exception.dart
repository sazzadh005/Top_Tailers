/// A user-facing error raised by the (mock) backend layer.
class AppException implements Exception {
  AppException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Converts any thrown object to a short, friendly message for the UI.
String errorText(Object error) {
  if (error is AppException) return error.message;
  return 'Something went wrong. Please try again.';
}
