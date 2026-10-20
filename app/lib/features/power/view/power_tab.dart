import 'dart:async';
import 'dart:math' as math;

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lanka_radar/app/motion.dart';
import 'package:lanka_radar/app/segments.dart';
import 'package:lanka_radar/core/data/power_cuts.dart';
import 'package:lanka_radar/core/links.dart';
import 'package:lanka_radar/core/location.dart';
import 'package:lanka_radar/features/power/cubit/power_cubit.dart';
import 'package:lanka_radar/features/power/hero_status.dart';
import 'package:lanka_radar/features/power/view/place_page.dart';
import 'package:lanka_radar/features/power/widgets/place_row.dart';
import 'package:lanka_radar/features/power/widgets/power_card.dart';

/// Power: how the places watched stand, from EDLCare's outage map, and the
/// places themselves.
class PowerTab extends StatelessWidget {
  const PowerTab({
    this.open = openExternally,
    this.locate = locatePhone,
    super.key,
  });

  /// EDLCare's outage map.
  static final outageMap = Uri.parse(
    'https://edlcare.edl.lk/incognito/outage-map',
  );

  final OpenLink open;
  final Locate locate;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PowerCubit, PowerState>(
      builder: (context, state) {
        final setup = state.setup;
        if (setup == null) {
          // Read from the phone in a moment; a spinner here would only flash.
          return const SizedBox.shrink();
        }
        final cubit = context.read<PowerCubit>();
        final status = heroStatusFor(state, now: DateTime.now());
        final places = setup.places;
        void showOutcome(PlaceOutcome? outcome) =>
            _showOutcome(context, cubit, outcome);
        Widget editor(Place place, {required bool isNew}) =>
            PlacePage.editor(cubit, place, isNew: isNew, locate: locate);
        void addPlace() => unawaited(
          Navigator.of(context)
              .push(
                MaterialPageRoute<PlaceOutcome>(
                  builder: (context) => editor(
                    Place(id: cubit.newId(), name: cubit.newName()),
                    isNew: true,
                  ),
                ),
              )
              .then(showOutcome),
        );
        if (places.isEmpty) {
          return _Invite(onAdd: addPlace);
        }
        final header = PowerCard(
          status: status,
          onRefresh: setup.ready.isEmpty
              ? null
              : () => unawaited(cubit.check()),
          onAction: () => switch (status.action) {
            HeroAction.add => addPlace(),
            HeroAction.finish => unawaited(
              Navigator.of(context)
                  .push(
                    MaterialPageRoute<PlaceOutcome>(
                      builder: (context) => editor(
                        places.firstWhere((place) => !place.ready),
                        isNew: false,
                      ),
                    ),
                  )
                  .then(showOutcome),
            ),
            HeroAction.retry || null => unawaited(cubit.check()),
          },
        );
        return RefreshIndicator(
          onRefresh: cubit.check,
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                sliver: SliverToBoxAdapter(child: header),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverToBoxAdapter(
                  child: SectionTitle(
                    'Places',
                    trailing: '${places.length} of ${PowerSetup.most}',
                    padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
                  ),
                ),
              ),
              _PlaceList(state: state, editor: editor, onClosed: showOutcome),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                sliver: SliverToBoxAdapter(
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      if (places.length < PowerSetup.most)
                        TextButton.icon(
                          onPressed: addPlace,
                          icon: const Icon(Icons.add),
                          label: const Text('Add a place'),
                        ),
                      TextButton.icon(
                        onPressed: () => unawaited(open(outageMap)),
                        icon: const Icon(Icons.map_outlined, size: 18),
                        label: const Text("EDLCare's outage map"),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// A word on what just happened to a place, with Undo for a removal.
  static void _showOutcome(
    BuildContext context,
    PowerCubit cubit,
    PlaceOutcome? outcome,
  ) {
    if (outcome == null || !context.mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    messenger.showSnackBar(switch (outcome) {
      PlaceSaved(:final place, isNew: true) => SnackBar(
        content: Text('${place.name} added. Checking for cuts there.'),
      ),
      PlaceSaved(:final place) => SnackBar(
        content: Text('Changes to ${place.name} saved'),
      ),
      PlaceRemoved(:final place, :final index) => SnackBar(
        content: Text('${place.name} removed'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => unawaited(cubit.restore(place, index)),
        ),
      ),
    });
  }
}

/// The places, arriving one after another the first time the list shows.
/// Each row grows into its page when tapped.
class _PlaceList extends StatefulWidget {
  const _PlaceList({
    required this.state,
    required this.editor,
    required this.onClosed,
  });

  final PowerState state;
  final Widget Function(Place place, {required bool isNew}) editor;
  final void Function(PlaceOutcome?) onClosed;

  @override
  State<_PlaceList> createState() => _PlaceListState();
}

class _PlaceListState extends State<_PlaceList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entrance.isDismissed) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _entrance.value = 1;
      } else {
        unawaited(_entrance.forward());
      }
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final state = widget.state;
    final places = state.setup!.places;
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList.separated(
        itemCount: places.length,
        separatorBuilder: (_, _) => const SizedBox(height: 3),
        itemBuilder: (context, index) {
          final place = places[index];
          final shape = segmentShape(index, places.length);
          // Starts after the top card, then one row after another.
          final start = math.min(0.15 + index * 0.08, 0.55);
          final arrival = _entrance.drive(
            CurveTween(
              curve: Interval(start, start + 0.45, curve: Motion.enter),
            ),
          );
          return FadeTransition(
            key: ValueKey(place.id),
            opacity: arrival,
            child: SlideTransition(
              position: arrival.drive(
                Tween(begin: const Offset(0, 0.25), end: Offset.zero),
              ),
              child: OpenContainer<PlaceOutcome>(
                transitionDuration: _containerDuration(context),
                transitionType: ContainerTransitionType.fadeThrough,
                closedElevation: 0,
                openElevation: 0,
                closedShape: shape,
                closedColor: colors.surfaceContainerLowest,
                openColor: colors.surface,
                middleColor: colors.surface,
                tappable: false,
                onClosed: widget.onClosed,
                closedBuilder: (context, open) => PlaceRow(
                  place: place,
                  state: nodeState(state, place),
                  cuts: state.cutsAt(place),
                  checking: state.check == PowerCheck.checking,
                  shape: shape,
                  onTap: open,
                ),
                openBuilder: (context, _) => widget.editor(place, isNew: false),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// With no place yet: what Power does, and the way to start.
class _Invite extends StatelessWidget {
  const _Invite({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Icon(
                Icons.add_location_alt_outlined,
                size: 40,
                color: colors.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Watch for power cuts',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Add home, work or any place. Power cuts there show here and on '
              'Today.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add a place'),
            ),
          ],
        ),
      ),
    );
  }
}

/// How long a card takes to grow into its page. Never zero: with animations
/// off, a zero-length transition leaves the card hidden after the page closes.
Duration _containerDuration(BuildContext context) {
  final duration = Motion.of(context, Motion.long);
  return duration == Duration.zero ? const Duration(milliseconds: 1) : duration;
}
