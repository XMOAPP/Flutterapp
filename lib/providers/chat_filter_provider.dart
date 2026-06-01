import 'package:flutter/material.dart';

enum ChatFilter { all, stories, groups, channels, calls }

// ═══════════════════════════════════════════════════════════════════════════
// OPTIMIZED CHAT FILTER PROVIDER
// ═══════════════════════════════════════════════════════════════════════════

class ChatFilterProvider extends ChangeNotifier {
  ChatFilter _filter = ChatFilter.all;
  String _searchQuery = '';

  ChatFilter get filter => _filter;
  String get searchQuery => _searchQuery;

  void setFilter(ChatFilter filter) {
    if (_filter == filter) return; // Prevent unnecessary rebuilds
    _filter = filter;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    if (_searchQuery == query) return; // Prevent unnecessary rebuilds
    _searchQuery = query;
    notifyListeners();
  }

  // Clear search without notifying if already empty
  void clearSearch() {
    if (_searchQuery.isEmpty) return;
    _searchQuery = '';
    notifyListeners();
  }
}
