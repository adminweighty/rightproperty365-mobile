import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import '../activity/activity_store.dart';
import '../auth/auth_controller.dart';
import '../listings/data/listing_repository.dart';
import 'saved_listings_repository.dart';

/// Which listings the signed-in account has saved, for the hearts on cards
/// and listing pages. Saving needs an account; signed out, nothing is held
/// (FR-045).
class SavedListings extends ChangeNotifier {
  SavedListings({
    required this.repository,
    required this._auth,
    required this._activity,
    required this._listings,
  }) {
    _auth.addListener(_onAuth);
    _onAuth();
  }

  final SavedListingsRepository repository;
  final AuthController _auth;
  final ActivityStore _activity;
  final ListingRepository _listings;

  Set<String> _ids = {};
  bool _wasSignedIn = false;

  /// Hearts tapped while a reload was on its way, so its answer (from
  /// before the tap) does not undo them.
  final Map<String, bool> _tapped = {};
  int _reloads = 0;

  bool get signedIn => _auth.signedIn;

  bool isSaved(String listingId) => _ids.contains(listingId);

  void _onAuth() {
    final now = _auth.signedIn;
    if (now == _wasSignedIn) return;
    _wasSignedIn = now;
    if (now) {
      refresh();
    } else {
      _ids = {};
      _tapped.clear();
      _reloads++;
      notifyListeners();
    }
  }

  /// Reloads the saved ids. Properties saved on this phone before saving
  /// needed an account are moved to the account first, then forgotten here.
  Future<void> refresh() async {
    final reload = ++_reloads;
    try {
      await _moveLocalSaves();
      final ids = await repository.ids();
      if (!_auth.signedIn || reload != _reloads) return;
      _ids = {...ids};
      _tapped.forEach((id, saved) => saved ? _ids.add(id) : _ids.remove(id));
      notifyListeners();
    } on ApiFailure {
      // The hearts stay as they were; the Saved tab shows its own error.
    } finally {
      if (reload == _reloads) _tapped.clear();
    }
  }

  Future<void> _moveLocalSaves() async {
    final slugs = _activity.savedSlugs;
    if (slugs.isEmpty) return;
    for (final slug in slugs) {
      final listing = await _listings.bySlug(slug);
      if (listing == null) continue;
      try {
        await repository.save(listing.id);
      } on ApiFailure catch (failure) {
        // A listing that is no longer public cannot be saved: drop it.
        if (failure.status != 404) rethrow;
      }
    }
    await _activity.clearSaved();
  }

  /// Saves or removes [listingId] at once and undoes it if the API refuses.
  /// Returns whether it is now saved. Throws [ApiFailure].
  Future<bool> toggle(String listingId) async {
    final saving = !_ids.contains(listingId);
    _set(listingId, saving);
    try {
      saving
          ? await repository.save(listingId)
          : await repository.remove(listingId);
      return saving;
    } on ApiFailure {
      _set(listingId, !saving);
      rethrow;
    }
  }

  /// Saves [listingId] (after signing in from a heart). Throws [ApiFailure].
  Future<void> save(String listingId) async {
    if (_ids.contains(listingId)) return;
    await toggle(listingId);
  }

  /// Forgets a listing removed from the Saved tab.
  Future<void> remove(String listingId) async {
    if (_ids.contains(listingId)) {
      await toggle(listingId);
    } else {
      await repository.remove(listingId);
    }
  }

  void _set(String id, bool saved) {
    _tapped[id] = saved;
    _ids = {..._ids};
    saved ? _ids.add(id) : _ids.remove(id);
    notifyListeners();
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuth);
    super.dispose();
  }
}
