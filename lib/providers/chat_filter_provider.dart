import 'package:flutter/material.dart';

enum ChatFilter { all, groups, stories }

class ChatFilterProvider extends ChangeNotifier {
  ChatFilter _filter = ChatFilter.all;
  String _searchQuery = '';

  ChatFilter get filter => _filter;
  String get searchQuery => _searchQuery;

  void setFilter(ChatFilter filter) {
    _filter = filter;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }
}
