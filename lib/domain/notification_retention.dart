import '../models/app_notification.dart';

/// Customer-facing notification retention (30 days).
///
/// Visible: age < 30 days, or exactly 30 days. Hidden: older than 30 days,
/// or no usable timestamp. Hiding is NOT deletion: permanent deletion is a
/// backend retention job.
class NotificationRetention {
  NotificationRetention._();

  static const Duration window = Duration(days: 30);

  static bool isVisible(AppNotification n, DateTime now) {
    final created = n.createdAt;
    if (created == null) return false;
    return now.difference(created) <= window;
  }

  /// Visible notifications, newest first.
  static List<AppNotification> visible(
    Iterable<AppNotification> all,
    DateTime now,
  ) {
    final list = all.where((n) => isVisible(n, now)).toList();
    list.sort((a, b) => b.createdAt!.compareTo(a.createdAt!));
    return list;
  }
}
