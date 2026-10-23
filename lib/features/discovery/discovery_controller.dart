import 'package:flutter/foundation.dart';

import '../../core/error_message.dart';
import '../../domain/catalog.dart';

/// One catalogue search: the query, the pages received so far, and where the
/// next request starts.
class SearchResults {
  const SearchResults({
    this.query = '',
    this.items = const [],
    this.offset = 0,
    this.total = 0,
    this.hasMore = false,
    this.error,
    this.requestOffset = 0,
  });
  final String query;
  final List<Subject> items;
  final int offset, total;
  final bool hasMore;
  final String? error;

  /// Offset of the latest request, retried on failure.
  final int requestOffset;
}

/// Home feeds, the weekly calendar and catalogue search.
class DiscoveryController extends ChangeNotifier {
  DiscoveryController(this.catalog);
  final Catalog catalog;

  List<Subject> trending = [], today = [];
  String? todayDate;
  bool trendingLoading = true, todayLoading = true;
  String? trendingError, todayError;
  List<ScheduleDay> calendar = [];
  bool calendarLoading = false;
  String? calendarError;
  SearchResults search = const SearchResults();
  bool searching = false;
  int _searchTicket = 0;

  /// Loads trending and today's schedule, showing cached values first.
  /// Returns a message when either failed.
  Future<String?> loadHome({bool refresh = false}) async {
    trendingLoading = todayLoading = true;
    trendingError = todayError = null;
    if (todayDate != null && todayDate != catalog.scheduleDate) today = [];
    notifyListeners();
    void showTrending(List<Subject> value) {
      trending = value;
      notifyListeners();
    }

    void showToday(SchedulePage value) {
      today = value.items;
      todayDate = value.date;
      notifyListeners();
    }

    var trendingFailed = false, todayFailed = false;
    await Future.wait([
      catalog
          .trending(refresh: refresh, limit: 8, onCached: showTrending)
          .then(showTrending)
          .catchError((Object e) {
            trendingFailed = true;
            trendingError = errorMessage(e);
          })
          .whenComplete(() {
            trendingLoading = false;
            notifyListeners();
          }),
      catalog
          .today(refresh: refresh, onCached: showToday)
          .then(showToday)
          .catchError((Object e) {
            todayFailed = true;
            todayError = errorMessage(e);
          })
          .whenComplete(() {
            todayLoading = false;
            notifyListeners();
          }),
    ]);
    if (trendingFailed && todayFailed) return '刷新失败，仍显示上次内容。';
    if (trendingFailed) return '今日放送已更新，本季热度刷新失败。';
    if (todayFailed) return '本季热度已更新，今日放送刷新失败。';
    return null;
  }

  Future<void> loadCalendar() async {
    calendarLoading = true;
    calendarError = null;
    notifyListeners();
    void show(List<ScheduleDay> value) {
      calendar = value;
      notifyListeners();
    }

    try {
      show(await catalog.calendar(onCached: show));
    } catch (e) {
      calendarError = errorMessage(e);
      rethrow;
    } finally {
      calendarLoading = false;
      notifyListeners();
    }
  }

  /// Starts a new search for [query].
  Future<void> searchSubjects(String query) {
    search = SearchResults(query: query);
    return _loadSearchPage(0);
  }

  Future<void> loadMore() async {
    if (searching || !search.hasMore) return;
    await _loadSearchPage(search.offset);
  }

  Future<void> retrySearch() => _loadSearchPage(search.requestOffset);

  /// Stops delivering the running search page.
  void cancelSearch() {
    _searchTicket++;
    searching = false;
  }

  /// Shows an earlier search again, reloading it when it was unfinished.
  void restoreSearch(SearchResults value, {required bool reload}) {
    cancelSearch();
    search = value;
    notifyListeners();
    if (reload) _loadSearchPage(value.requestOffset);
  }

  Future<void> _loadSearchPage(int offset) async {
    final ticket = ++_searchTicket;
    final previous = search.items.take(offset).toList();
    final query = search.query;
    searching = true;
    search = SearchResults(
      query: query,
      items: search.items,
      offset: search.offset,
      total: search.total,
      hasMore: search.hasMore,
      requestOffset: offset,
    );
    notifyListeners();
    void showPage(SubjectResults page) {
      if (ticket != _searchTicket) return;
      search = SearchResults(
        query: query,
        items: [...previous, ...page.items],
        offset: page.offset,
        total: page.total,
        hasMore: page.hasMore,
        requestOffset: offset,
      );
      notifyListeners();
    }

    try {
      showPage(await catalog.search(query, offset: offset, onCached: showPage));
    } catch (e) {
      if (ticket == _searchTicket) {
        search = SearchResults(
          query: query,
          items: search.items,
          offset: search.offset,
          total: search.total,
          hasMore: search.hasMore,
          error: errorMessage(e),
          requestOffset: offset,
        );
      }
    }
    if (ticket == _searchTicket) {
      searching = false;
      notifyListeners();
    }
  }
}
