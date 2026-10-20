import 'package:flutter/material.dart';

/// Rounds only the outer corners of a group, as Android's settings lists do.
ShapeBorder segmentShape(int index, int count) {
  const outer = Radius.circular(24);
  const inner = Radius.circular(6);
  return RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(
      top: index == 0 ? outer : inner,
      bottom: index == count - 1 ? outer : inner,
    ),
  );
}

/// The small heading over a group of rows or controls.
class SectionTitle extends StatelessWidget {
  const SectionTitle(
    this.text, {
    this.padding = const EdgeInsets.fromLTRB(4, 24, 4, 10),
    this.trailing,
    super.key,
  });

  final String text;
  final EdgeInsetsGeometry padding;

  /// A quiet note at the end of the line, such as a count.
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.titleSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(child: Text(text, style: style)),
          if (trailing case final trailing?)
            Text(
              trailing,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

/// A titled group of rows, each on its own segment of one rounded block.
class GroupedSection extends StatelessWidget {
  const GroupedSection({required this.children, this.title, super.key});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title case final title?) SectionTitle(title),
        for (final (index, child) in children.indexed) ...[
          if (index > 0) const SizedBox(height: 3),
          Material(
            color: theme.colorScheme.surfaceContainerLowest,
            shape: segmentShape(index, children.length),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
        ],
      ],
    );
  }
}
