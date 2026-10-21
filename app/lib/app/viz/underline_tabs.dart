import 'package:flutter/material.dart';
import 'package:lanka_radar/app/motion.dart';

/// A row of names with a line under the one picked, which slides to the next
/// one picked. Scrolls sideways when the names don't fit.
class UnderlineTabs extends StatefulWidget {
  const UnderlineTabs({
    required this.labels,
    required this.selected,
    required this.onSelected,
    this.padding = const EdgeInsets.symmetric(horizontal: 4),
    this.dense = false,
    super.key,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;
  final EdgeInsetsGeometry padding;

  /// Smaller, for a row inside a group.
  final bool dense;

  @override
  State<UnderlineTabs> createState() => _UnderlineTabsState();
}

class _UnderlineTabsState extends State<UnderlineTabs>
    with TickerProviderStateMixin {
  late TabController _tabs = _controller();

  TabController _controller() => TabController(
    length: widget.labels.length,
    initialIndex: widget.selected.clamp(0, widget.labels.length - 1),
    vsync: this,
    animationDuration: Motion.medium,
  );

  @override
  void didUpdateWidget(UnderlineTabs old) {
    super.didUpdateWidget(old);
    if (old.labels.length != widget.labels.length) {
      _tabs.dispose();
      _tabs = _controller();
    } else if (widget.selected != _tabs.index) {
      _tabs.animateTo(
        widget.selected,
        duration: Motion.of(context, Motion.medium),
        curve: Motion.standard,
      );
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final style = widget.dense
        ? theme.textTheme.labelLarge?.copyWith(fontSize: 14)
        : theme.textTheme.titleSmall?.copyWith(fontSize: 15);
    return TabBar(
      controller: _tabs,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      padding: widget.padding,
      labelPadding: EdgeInsets.symmetric(horizontal: widget.dense ? 10 : 12),
      dividerColor: Colors.transparent,
      overlayColor: WidgetStatePropertyAll(
        colors.primary.withValues(alpha: 0.08),
      ),
      splashBorderRadius: BorderRadius.circular(12),
      labelColor: colors.onSurface,
      unselectedLabelColor: colors.onSurfaceVariant,
      labelStyle: style,
      unselectedLabelStyle: style?.copyWith(fontWeight: FontWeight.w500),
      indicatorSize: TabBarIndicatorSize.label,
      indicator: UnderlineTabIndicator(
        borderSide: BorderSide(color: colors.primary, width: 3),
        borderRadius: BorderRadius.circular(3),
        insets: const EdgeInsets.only(bottom: 4),
      ),
      onTap: widget.onSelected,
      tabs: [
        for (final label in widget.labels)
          Tab(height: widget.dense ? 38 : 44, text: label),
      ],
    );
  }
}
