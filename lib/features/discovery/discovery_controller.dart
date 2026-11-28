import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/error_message.dart';
import '../../domain/catalog.dart';

/// One catalogue search: the query, the pages received so far, and where the
/// next request starts.
class SearchResults {
  const SearchResults({
    this.query = const SubjectQuery(),
    this.items = const [],
    this.offset = 0,
    this.total = 0,
    this.hasMore = false,
    this.error,
    this.requestOffset = 0,
  });
  final SubjectQuery query;
  final List<Subject> items;
  final int offset, total;
  final bool hasMore;
  final String? error;

  /// Offset of the latest request, retried on failure.
  final int requestOffset;

  /// These results while the page at [offset] loads, or after it failed
  /// with [error].
  SearchResults requesting(int offset, {String? error}) => SearchResults(
    query: query,
    items: items,
    offset: this.offset,
    total: total,
    hasMore: hasMore,
    error: error,
    requestOffset: offset,
  );
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
  int _searchTicket = 0, _homeTicket = 0, _calendarTicket = 0;

  /// Loads trending and today's schedule, showing cached values first, and
  /// returns a message when either failed. A newer load drops the results
  /// and failures of one still running.
  Future<String?> loadHome({bool refresh = false}) async {
    final ticket = ++_homeTicket;
    bool current() => ticket == _homeTicket;
    trendingLoading = todayLoading = true;
    trendingError = todayError = null;
    if (todayDate != null && todayDate != catalog.scheduleDate) today = [];
    notifyListeners();
    void showTrending(List<Subject> value) {
      if (!current()) return;
      trending = value;
      notifyListeners();
    }

    void showToday(SchedulePage value) {
      if (!current()) return;
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
            if (!current()) return;
            trendingFailed = true;
            trendingError = errorMessage(e);
          })
          .whenComplete(() {
            if (!current()) return;
            trendingLoading = false;
            notifyListeners();
          }),
      catalog
          .today(refresh: refresh, onCached: showToday)
          .then(showToday)
          .catchError((Object e) {
            if (!current()) return;
            todayFailed = true;
            todayError = errorMessage(e);
          })
          .whenComplete(() {
            if (!current()) return;
            todayLoading = false;
            notifyListeners();
          }),
    ]);
    if (!current()) return null;
    if (trendingFailed && todayFailed) {
      return trending.isNotEmpty || today.isNotEmpty
          ? '刷新失败，仍显示上次内容'
          : '刷新失败：${trendingError ?? todayError}';
    }
    if (trendingFailed) return '今日放送已更新，本季热度刷新失败';
    if (todayFailed) return '本季热度已更新，今日放送刷新失败';
    return null;
  }

  /// Whether a failed home feed still shows its earlier content, so its
  /// failure has no place on the page; an empty feed names it there.
  bool get homeShowsStale =>
      (trendingError != null && trending.isNotEmpty) ||
      (todayError != null && today.isNotEmpty);

  /// Loads the weekly calendar, showing cached days first; a failure stays
  /// in [calendarError] for the calendar page to show.
  Future<void> loadCalendar() async {
    final ticket = ++_calendarTicket;
    calendarLoading = true;
    calendarError = null;
    notifyListeners();
    void show(List<ScheduleDay> value) {
      if (ticket != _calendarTicket) return;
      calendar = value;
      notifyListeners();
    }

    try {
      show(await catalog.calendar(onCached: show));
    } catch (e) {
      if (ticket == _calendarTicket) calendarError = errorMessage(e);
    } finally {
      if (ticket == _calendarTicket) {
        calendarLoading = false;
        notifyListeners();
      }
    }
  }

  /// The Monday of the schedule week shown, `yyyy-MM-dd`; this week's until
  /// another is chosen.
  String get weekMonday => _weekMonday ?? mondayOf(catalog.scheduleDate);
  String? _weekMonday;
  ScheduleWeek? week;
  bool weekLoading = false;
  String? weekError;
  int _weekTicket = 0, _weekRetries = 0;
  Timer? _weekRetry;

  /// The Monday, `yyyy-MM-dd`, of the week holding [date].
  static String mondayOf(String date) {
    final day = DateTime.parse('${date}T00:00:00Z');
    return day
        .subtract(Duration(days: day.weekday - 1))
        .toIso8601String()
        .substring(0, 10);
  }

  /// Loads the schedule week starting [monday], by default the one shown,
  /// showing a cached copy first; a failure stays in [weekError]. While the
  /// Melon API is still fetching some shows' details, the week loads again
  /// a little later, a few times.
  Future<void> loadWeek([String? monday]) async {
    final target = monday ?? weekMonday;
    final ticket = ++_weekTicket;
    _weekRetry?.cancel();
    if (target != weekMonday) {
      _weekRetries = 0;
      week = null;
    }
    _weekMonday = target;
    weekLoading = true;
    weekError = null;
    notifyListeners();
    void show(ScheduleWeek value) {
      if (ticket != _weekTicket) return;
      week = value;
      notifyListeners();
    }

    try {
      show(await catalog.week(target, onCached: show));
      if (ticket == _weekTicket && week!.incomplete > 0 && _weekRetries++ < 5) {
        // The API keeps a week missing details for a minute.
        _weekRetry = Timer(const Duration(seconds: 65), () => loadWeek(target));
      }
    } catch (e) {
      if (ticket == _weekTicket) weekError = errorMessage(e);
    } finally {
      if (ticket == _weekTicket) {
        weekLoading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _weekRetry?.cancel();
    super.dispose();
  }

  /// Starts a new search for [query].
  Future<void> searchSubjects(SubjectQuery query) {
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
    search = search.requesting(offset);
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
        search = search.requesting(offset, error: errorMessage(e));
      }
    }
    if (ticket == _searchTicket) {
      searching = false;
      notifyListeners();
    }
  }
}
