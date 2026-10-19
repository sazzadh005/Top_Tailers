/// A customer notification. [createdAt] may be null when a server record has
/// a missing or unreadable timestamp; such entries are never shown.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.userId,
    required this.title,
    required this.body,
    required this.createdAt,
    this.read = false,
  });

  final String id;
  final String userId;
  final String title;
  final String body;
  final DateTime? createdAt;
  final bool read;

  /// Tolerant parser for API/Firestore-style maps (timestamp as ISO text).
  factory AppNotification.fromMap(Map<String, Object?> map) {
    final raw = map['createdAt'];
    return AppNotification(
      id: '${map['id'] ?? ''}',
      userId: '${map['userId'] ?? ''}',
      title: '${map['title'] ?? ''}',
      body: '${map['body'] ?? ''}',
      createdAt: raw is String ? DateTime.tryParse(raw) : null,
      read: map['read'] == true,
    );
  }

  AppNotification copyWith({bool? read}) {
    return AppNotification(
      id: id,
      userId: userId,
      title: title,
      body: body,
      createdAt: createdAt,
      read: read ?? this.read,
    );
  }
}
