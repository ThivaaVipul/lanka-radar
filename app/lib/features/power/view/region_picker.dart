import 'package:flutter/material.dart';
import 'package:lanka_radar/core/data/power_cuts.dart';

/// A row that shows the province or area picked and opens [pickRegion].
class RegionTile extends StatelessWidget {
  const RegionTile({
    required this.label,
    required this.picked,
    required this.options,
    required this.onPicked,
    this.loading = false,
    super.key,
  });

  final String label;
  final CebRegion? picked;

  /// Null while there is nothing to pick from.
  final List<CebRegion>? options;
  final ValueChanged<CebRegion> onPicked;

  /// The options are on their way.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = this.options;
    final enabled = options != null && options.isNotEmpty;
    return ListTile(
      enabled: enabled,
      title: Text(label),
      subtitle: Text(
        picked?.name ?? 'Not picked',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: picked == null
              ? theme.colorScheme.onSurfaceVariant
              : theme.colorScheme.onSurface,
        ),
      ),
      trailing: loading
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chevron_right),
      onTap: !enabled
          ? null
          : () async {
              final chosen = await pickRegion(
                context,
                title: label,
                options: options,
                picked: picked,
              );
              if (chosen != null) {
                onPicked(chosen);
              }
            },
    );
  }
}

/// A sheet listing [options], the [picked] one ticked; gives the one tapped.
Future<CebRegion?> pickRegion(
  BuildContext context, {
  required String title,
  required List<CebRegion> options,
  CebRegion? picked,
}) => showModalBottomSheet<CebRegion>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(title, style: theme.textTheme.titleMedium),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                for (final option in options)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    title: Text(option.name),
                    selected: option == picked,
                    trailing: option == picked ? const Icon(Icons.check) : null,
                    onTap: () => Navigator.of(context).pop(option),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  },
);
