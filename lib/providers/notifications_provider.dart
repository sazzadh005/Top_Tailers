import 'package:flutter/foundation.dart';

import '../models/app_notification.dart';
import '../repositories/repositories.dart';
import 'load_state.dart';

class NotificationsProvider extends ChangeNotifier {
  NotificationsProvider(this._repo);

  final NotificationRepository _repo;

  List<AppNotification> _items = [];
  LoadState _state = LoadState.idle;
  String? _userId;

  List<AppNotification> get items => _items;
  LoadState get state => _state;
  int get unreadCount => _items.where((n) => !n.read).length;

  /// Refreshes the visible list (the repository applies the 30-day rule).
  Future<void> load(String userId) async {
    _userId = userId;
    _state = LoadState.loading;
    notifyListeners();
    try {
      _items = await _repo.getVisible(userId);
      _state = LoadState.ready;
    } catch (_) {
      _state = LoadState.error;
    }
    notifyListeners();
  }

  Future<void> markAllRead() async {
    final userId = _userId;
    if (userId == null) return;
    await _repo.markAllRead(userId);
    _items = [for (final n in _items) n.copyWith(read: true)];
    notifyListeners();
  }

  void reset() {
    _items = [];
    _userId = null;
    _state = LoadState.idle;
    notifyListeners();
  }
}
