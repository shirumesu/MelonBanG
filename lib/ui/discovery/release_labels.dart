import '../../domain/episode_release.dart';

const weekdayLabels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

/// When [release] comes: minutes within the last hour, then 今天 / 明天 /
/// 周X with the hour within a week, else the date. A time ends in a space,
/// ready for 更新 to follow.
String releaseWhen(Release release) {
  final (:at, :timed) = release;
  final now = DateTime.now();
  final left = at.difference(now);
  final day = timed ? shanghaiDay(at) : DateTime.utc(at.year, at.month, at.day);
  final today = shanghaiDay(now);
  final clock = timed ? ' ${shanghaiClock(at)} ' : '';
  return timed && left < const Duration(hours: 1)
      ? left.inMinutes < 1
            ? '即将'
            : '${left.inMinutes} 分钟后'
      : switch (day.difference(today).inDays) {
          <= 0 => '今天$clock',
          1 => '明天$clock',
          < 7 => '${weekdayLabels[day.weekday - 1]}$clock',
          _ when day.year == today.year => '${day.month}月${day.day}日',
          _ => '${day.year}年${day.month}月${day.day}日',
        };
}
