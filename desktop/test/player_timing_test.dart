import 'package:flutter_test/flutter_test.dart';
import 'package:melonbang/danmaku.dart';
import 'package:melonbang/player_page.dart';

void main() {
  test(
    'seek finds the active comment window without replaying old comments',
    () {
      final comments = [
        {'timeSeconds': 2, 'text': 'a'},
        {'timeSeconds': 90, 'text': 'b'},
        {'timeSeconds': 90, 'text': 'c'},
        {'timeSeconds': 120, 'text': 'd'},
      ];
      expect(firstVisibleComment(comments, 90), 1);
      expect(firstVisibleComment(comments, 110), 3);
      expect(firstVisibleComment(comments, 0), 0);
      expect(firstVisibleComment(comments, 121), 4);
      expect(firstVisibleComment([], 10), 0);
    },
  );
  test('time labels preserve long episodes and handle unknown duration', () {
    expect(formatTime(3661), '61:01');
    expect(formatTime(double.nan), '00:00');
    expect(formatTime(-1), '00:00');
  });
}
