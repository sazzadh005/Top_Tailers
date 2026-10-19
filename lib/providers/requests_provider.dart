import 'package:flutter/foundation.dart';

import '../models/requests.dart';
import '../repositories/repositories.dart';
import 'load_state.dart';

/// Product suggestions and restock requests (customer and admin sides).
class RequestsProvider extends ChangeNotifier {
  RequestsProvider(this._repo);

  final RequestRepository _repo;

  List<ProductSuggestion> _suggestions = [];
  List<RestockRequest> _restocks = [];
  LoadState _state = LoadState.idle;
  String? _error;

  List<ProductSuggestion> get suggestions => _suggestions;
  List<RestockRequest> get restocks => _restocks;
  LoadState get state => _state;
  String? get error => _error;

  Future<void> loadMine(String userId) async {
    _state = LoadState.loading;
    notifyListeners();
    try {
      _suggestions = await _repo.suggestionsFor(userId);
      _restocks = await _repo.restocksFor(userId);
      _state = LoadState.ready;
    } catch (e) {
      _error = e.toString();
      _state = LoadState.error;
    }
    notifyListeners();
  }

  Future<void> loadAll() async {
    _state = LoadState.loading;
    notifyListeners();
    try {
      _suggestions = await _repo.allSuggestions();
      _restocks = await _repo.allRestocks();
      _state = LoadState.ready;
    } catch (e) {
      _error = e.toString();
      _state = LoadState.error;
    }
    notifyListeners();
  }

  Future<void> submitSuggestion(ProductSuggestion draft) async {
    final saved = await _repo.submitSuggestion(draft);
    _suggestions = [saved, ..._suggestions];
    notifyListeners();
  }

  Future<void> submitRestock(RestockRequest draft) async {
    final saved = await _repo.submitRestock(draft);
    _restocks = [saved, ..._restocks];
    notifyListeners();
  }

  Future<void> setSuggestionStatus(String id, RequestStatus status) async {
    await _repo.setSuggestionStatus(id, status);
    _suggestions = [for (final s in _suggestions) s.id == id ? s.copyWith(status: status) : s];
    notifyListeners();
  }

  Future<void> setRestockStatus(String id, RequestStatus status) async {
    await _repo.setRestockStatus(id, status);
    _restocks = [for (final r in _restocks) r.id == id ? r.copyWith(status: status) : r];
    notifyListeners();
  }

  void reset() {
    _suggestions = [];
    _restocks = [];
    _state = LoadState.idle;
    notifyListeners();
  }
}
