import 'package:flutter/material.dart';

import '../core/notices.dart';
import '../ui/core/account_avatar.dart';
import '../ui/core/motion.dart';
import '../ui/core/sidebar_tile.dart';
import '../ui/core/theme.dart';
import '../ui/core/tone.dart';

class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.route,
    required this.nickname,
    required this.onNavigate,
    this.watchingCount = 0,
    this.downloadCount = 0,
    this.attentionCount = 0,
    this.attentionFailed = false,
    this.username,
    this.avatarUrl,
    this.selectedRoute,
    this.sourcesWarning = false,
    this.accountIssue,
  });
  final String route, nickname;
  final String? username, avatarUrl;

  /// Why the signed-in account cannot sync, shown in place of its handle.
  final String? accountIssue;
  final String? selectedRoute;
  final int watchingCount, downloadCount;

  /// Subscriptions waiting on the user, marked on 缓存 where they show:
  /// failed when one of them failed, a warning when episodes are only late.
  final int attentionCount;
  final bool attentionFailed;
  final bool sourcesWarning;
  final ValueChanged<String> onNavigate;

  /// The entry standing for the current page; detail pages reached from
  /// 首页 keep it selected.
  String? get _selected {
    final active = selectedRoute ?? route;
    if (const ['subject', 'calendar', 'search', 'resources'].contains(active)) {
      return 'home';
    }
    return const [
          'home',
          'tracking',
          'downloads',
          'sources',
          'settings',
        ].contains(active)
        ? active
        : null;
  }

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(gradient: sidebarSurface(context)),
    child: Stack(
      fit: StackFit.expand,
      children: [
        // The top edge fades into the title bar the way the right edge
        // fades into the page.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: Gap.xl,
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: sidebarTopFade(context)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(Gap.md),
          // One highlight glides between entries instead of each lighting up.
          child: MotionSelection<String>(
            selected: _selected,
            highlight: sidebarHighlight(context),
            builder: (context, keyOf) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: Gap.lg),
                  child: Tooltip(
                    message: '返回首页',
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: controlBorderRadius,
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        key: const ValueKey('brand-home'),
                        onTap: () => onNavigate('home'),
                        child: Semantics(
                          button: true,
                          label: 'MelonBanG，返回首页',
                          excludeSemantics: true,
                          child: Padding(
                            padding: const EdgeInsets.all(Gap.sm),
                            child: Image.asset(
                              'assets/images/logotype.png',
                              width: 150,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                _nav(context, keyOf, 'home', '首页', Icons.explore_outlined),
                _nav(
                  context,
                  keyOf,
                  'tracking',
                  '追番',
                  Icons.favorite_border,
                  watchingCount > 0 ? '$watchingCount' : null,
                ),
                _nav(
                  context,
                  keyOf,
                  'downloads',
                  '缓存',
                  Icons.download_outlined,
                  downloadCount > 0 ? '$downloadCount' : null,
                  attentionCount > 0 ? '有订阅需要处理' : null,
                  attentionFailed ? NoticeTone.failed : NoticeTone.warning,
                ),
                const Spacer(),
                _nav(
                  context,
                  keyOf,
                  'sources',
                  '数据源',
                  Icons.hub_outlined,
                  null,
                  sourcesWarning ? '有数据源需要处理' : null,
                  NoticeTone.warning,
                ),
                _nav(context, keyOf, 'settings', '设置', Icons.settings_outlined),
                const SizedBox(height: Gap.sm),
                Material(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: controlBorderRadius,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => onNavigate('settings'),
                    child: Padding(
                      padding: const EdgeInsets.all(Gap.sm),
                      child: Row(
                        children: [
                          AccountAvatar(
                            url: avatarUrl,
                            name: username == null ? '' : nickname,
                            size: 32,
                          ),
                          const SizedBox(width: Gap.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  nickname,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: FontSize.small,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                                Text(
                                  accountIssue ??
                                      (username == null
                                          ? '登录 Bangumi'
                                          : '@$username'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: FontSize.caption,
                                    color: accountIssue == null
                                        ? Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant
                                        : toneColor(context, NoticeTone.failed),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _nav(
    BuildContext context,
    Key Function(String) keyOf,
    String target,
    String label,
    IconData icon, [
    String? count,

    /// What the dot marking something to deal with says; null for no dot.
    String? alert,
    NoticeTone tone = NoticeTone.failed,
  ]) {
    final selected = _selected == target;
    final accent = accentOf(context);
    final dot = Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        color: toneColor(context, tone),
        shape: BoxShape.circle,
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.xs),
      child: SidebarTile(
        key: keyOf(target),
        label: label,
        icon: icon,
        selected: selected,
        onTap: () => onNavigate(target),
        trailing: count == null && alert == null
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (count != null)
                    _CountBump(
                      count: count,
                      child: MotionSwap(
                        value: count,
                        scale: .6,
                        child: AnimatedDefaultTextStyle(
                          duration: motionDuration(context, 200),
                          style: appFont.copyWith(
                            fontSize: FontSize.caption,
                            color: selected
                                ? accent.onNavigation
                                : Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                          child: Text(count),
                        ),
                      ),
                    ),
                  if (alert != null) ...[
                    if (count != null) const SizedBox(width: Gap.sm),
                    Tooltip(
                      message: alert,
                      child: Semantics(label: alert, child: dot),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

/// Swells a sidebar count for a moment when it grows, such as a download
/// just added from another page, so the eye finds where it went.
class _CountBump extends StatefulWidget {
  const _CountBump({required this.count, required this.child});
  final String count;
  final Widget child;

  @override
  State<_CountBump> createState() => _CountBumpState();
}

class _CountBumpState extends State<_CountBump>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 1.4,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 35,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.4,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeIn)),
      weight: 65,
    ),
  ]).animate(_controller);

  /// When the first count showed: counts restored as the app starts
  /// appear without a swell.
  static DateTime? _firstShown;

  @override
  void initState() {
    super.initState();
    final first = _firstShown ??= DateTime.now();
    // A count appearing later went from none to one or more.
    if (DateTime.now().difference(first) > const Duration(seconds: 3)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _bump());
    }
  }

  @override
  void didUpdateWidget(_CountBump oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = int.tryParse(oldWidget.count) ?? 0;
    final after = int.tryParse(widget.count) ?? 0;
    if (after > before) _bump();
  }

  void _bump() {
    if (mounted && !MediaQuery.disableAnimationsOf(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ScaleTransition(scale: _scale, child: widget.child);
}
