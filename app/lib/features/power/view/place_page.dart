import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:lanka_radar/app/motion.dart';
import 'package:lanka_radar/app/segments.dart';
import 'package:lanka_radar/core/data/power_cuts.dart';
import 'package:lanka_radar/core/location.dart';
import 'package:lanka_radar/features/power/cubit/place_cubit.dart';
import 'package:lanka_radar/features/power/cubit/power_cubit.dart';
import 'package:lanka_radar/features/power/view/map_picker_page.dart';
import 'package:lanka_radar/features/power/view/region_picker.dart';
import 'package:lanka_radar/features/power/widgets/osm.dart';

/// What happened to a place on its page.
sealed class PlaceOutcome {
  const PlaceOutcome(this.place);

  final Place place;
}

final class PlaceSaved extends PlaceOutcome {
  const PlaceSaved(super.place, {required this.isNew});

  final bool isNew;
}

final class PlaceRemoved extends PlaceOutcome {
  const PlaceRemoved(super.place, this.index);

  /// Where it was in the list, to put it back.
  final int index;
}

/// One place, added or changed as a draft: its name, where it is and its CEB
/// area, kept only on Save.
class PlacePage extends StatelessWidget {
  const PlacePage({required this.locate, super.key});

  /// The page with what it needs, for a route or an opening container.
  static Widget editor(
    PowerCubit power,
    Place place, {
    required bool isNew,
    Locate locate = locatePhone,
  }) => MultiBlocProvider(
    providers: [
      BlocProvider.value(value: power),
      BlocProvider(
        create: (context) =>
            PlaceCubit(context.read(), locate, place, isNew: isNew)
              ..loadRegions(),
      ),
    ],
    child: PlacePage(locate: locate),
  );

  /// Names to pick from instead of typing.
  static const names = ['Home', 'Work', 'School', 'Family'];

  final Locate locate;

  @override
  Widget build(BuildContext context) => _PlaceView(locate: locate);
}

class _PlaceView extends StatefulWidget {
  const _PlaceView({required this.locate});

  final Locate locate;

  @override
  State<_PlaceView> createState() => _PlaceViewState();
}

class _PlaceViewState extends State<_PlaceView> {
  late final _name = TextEditingController(
    text: context.read<PlaceCubit>().state.draft.name,
  );
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    final cubit = context.read<PlaceCubit>();
    final place = cubit.trySave();
    if (place == null) {
      unawaited(HapticFeedback.mediumImpact());
      return;
    }
    setState(() => _saving = true);
    await context.read<PowerCubit>().save(place);
    navigator.pop(PlaceSaved(place, isNew: cubit.state.isNew));
  }

  Future<void> _remove() async {
    final navigator = Navigator.of(context);
    final power = context.read<PowerCubit>();
    final place = context.read<PlaceCubit>().state.original!;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.wrong_location_outlined),
        title: Text('Remove ${place.name}?'),
        content: const Text("You'll stop seeing its power cuts."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (sure ?? false) {
      final index = await power.remove(place.id);
      navigator.pop(PlaceRemoved(place, index));
    }
  }

  Future<void> _pickOnMap() async {
    final cubit = context.read<PlaceCubit>();
    final draft = cubit.state.draft;
    final point = await Navigator.of(context).push(
      MapPickerPage.route(
        locate: widget.locate,
        initial: draft.point,
        name: draft.name.trim().isEmpty ? 'the place' : draft.name.trim(),
      ),
    );
    if (point != null) {
      cubit.setPoint(point);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PlaceCubit, PlaceState>(
      builder: (context, state) {
        final cubit = context.read<PlaceCubit>();
        final draft = state.draft;
        final point = draft.point;
        return PopScope(
          canPop: !state.changed || _saving,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) {
              return;
            }
            final navigator = Navigator.of(context);
            if (await _discard(context)) {
              navigator.pop();
            }
          },
          child: Scaffold(
            appBar: AppBar(
              leading: IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              title: Text(state.isNew ? 'New place' : 'Edit place'),
              actions: [
                if (!state.isNew)
                  IconButton(
                    tooltip: 'Remove place',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => unawaited(_remove()),
                  ),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _NameField(
                  controller: _name,
                  autofocus: state.isNew,
                  error: state.nameError,
                  attempts: state.attempts,
                  onChanged: cubit.rename,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final name in PlacePage.names)
                      ChoiceChip(
                        label: Text(name),
                        selected: draft.name.trim() == name,
                        onSelected: (_) {
                          _name.text = name;
                          cubit.rename(name);
                        },
                      ),
                  ],
                ),
                const SectionTitle('Where it is'),
                AnimatedSwitcher(
                  duration: Motion.of(context, Motion.medium),
                  child: point == null
                      ? _NoLocation(
                          key: const ValueKey('none'),
                          error: state.pointError,
                          locating: state.locating,
                          onPick: () => unawaited(_pickOnMap()),
                          onLocate: () => unawaited(cubit.locate()),
                        )
                      : _MapPreview(
                          key: const ValueKey('map'),
                          point: point,
                          onChange: () => unawaited(_pickOnMap()),
                        ),
                ),
                RevealSwitcher(
                  child: state.failure == null
                      ? const SizedBox(
                          key: ValueKey('ok'),
                          width: double.infinity,
                        )
                      : _Note(
                          key: ValueKey(state.failure),
                          text: locateMessage(state.failure!),
                          error: true,
                        ),
                ),
                GroupedSection(
                  title: 'CEB area',
                  children: [
                    RegionTile(
                      label: 'Province',
                      picked: draft.province,
                      options: state.provinces,
                      loading: state.provinces == null && !state.regionsFailed,
                      onPicked: (province) =>
                          unawaited(cubit.pickProvince(province)),
                    ),
                    RegionTile(
                      label: 'Area',
                      picked: draft.area,
                      options: state.provinceAreas,
                      loading:
                          draft.province != null &&
                          state.provinceAreas == null &&
                          !state.regionsFailed,
                      onPicked: cubit.pickArea,
                    ),
                    if (state.regionsFailed)
                      ListTile(
                        leading: const Icon(Icons.refresh),
                        title: const Text("EDLCare isn't answering"),
                        subtitle: const Text('Tap to try again'),
                        onTap: () => unawaited(cubit.loadRegions()),
                      ),
                  ],
                ),
                RevealSwitcher(
                  child: state.areaError == null
                      ? const SizedBox(
                          key: ValueKey('ok'),
                          width: double.infinity,
                        )
                      : _Note(
                          key: const ValueKey('area'),
                          text: state.areaError!,
                          error: true,
                        ),
                ),
              ],
            ),
            bottomNavigationBar: _SaveBar(
              label: state.isNew ? 'Add place' : 'Save changes',
              saving: _saving,
              onSave: () => unawaited(_save()),
            ),
          ),
        );
      },
    );
  }

  static Future<bool> _discard(BuildContext context) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard changes?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Discard'),
            ),
          ],
        ),
      ) ??
      false;
}

/// The place's name: a labelled field, focused on a new place, that shakes
/// and says so when Save finds it empty.
class _NameField extends StatefulWidget {
  const _NameField({
    required this.controller,
    required this.autofocus,
    required this.error,
    required this.attempts,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool autofocus;
  final String? error;
  final int attempts;
  final ValueChanged<String> onChanged;

  @override
  State<_NameField> createState() => _NameFieldState();
}

class _NameFieldState extends State<_NameField>
    with SingleTickerProviderStateMixin {
  late final _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void didUpdateWidget(_NameField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final triedAgain = widget.attempts != oldWidget.attempts;
    if (triedAgain &&
        widget.error != null &&
        !MediaQuery.disableAnimationsOf(context)) {
      unawaited(_shake.forward(from: 0));
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shake,
      // Three quick swings that settle, like a head shake.
      builder: (context, child) => Transform.translate(
        offset: Offset(
          math.sin(_shake.value * math.pi * 6) * 10 * (1 - _shake.value),
          0,
        ),
        child: child,
      ),
      child: TextField(
        controller: widget.controller,
        autofocus: widget.autofocus && widget.controller.text.isEmpty,
        decoration: InputDecoration(
          labelText: 'Name',
          hintText: 'Home, office or school',
          errorText: widget.error,
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainerLowest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
        style: Theme.of(context).textTheme.titleMedium,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        inputFormatters: [LengthLimitingTextInputFormatter(30)],
        onChanged: widget.onChanged,
      ),
    );
  }
}

/// A place without a point yet: the two ways to set one.
class _NoLocation extends StatelessWidget {
  const _NoLocation({
    required this.error,
    required this.locating,
    required this.onPick,
    required this.onLocate,
    super.key,
  });

  final String? error;
  final bool locating;
  final VoidCallback onPick;
  final VoidCallback onLocate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return AnimatedContainer(
      duration: Motion.of(context, Motion.medium),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: error == null ? Colors.transparent : colors.error,
          width: 1.5,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Column(
        children: [
          Icon(Icons.map_outlined, size: 40, color: colors.primary),
          const SizedBox(height: 10),
          Text(
            error ?? 'Put a pin where it is',
            style: theme.textTheme.titleMedium?.copyWith(
              color: error == null ? null : colors.error,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Put the pin on the building.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: onPick,
                icon: const Icon(Icons.map_outlined),
                label: const Text('Pick on map'),
              ),
              OutlinedButton.icon(
                onPressed: locating ? null : onLocate,
                icon: AnimatedSwitcher(
                  duration: Motion.of(context, Motion.short),
                  child: locating
                      ? const SizedBox.square(
                          key: ValueKey('locating'),
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location, key: ValueKey('icon')),
                ),
                label: const Text('Use my location'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The place on a small map, and a button to move it.
class _MapPreview extends StatelessWidget {
  const _MapPreview({required this.point, required this.onChange, super.key});

  final GeoPoint point;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final center = latLng(point);
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: SizedBox(
        height: 196,
        child: Stack(
          children: [
            FlutterMap(
              // Map options only apply to a new map, so a moved place gets one.
              key: ValueKey(point),
              options: MapOptions(
                initialCenter: center,
                initialZoom: MapPickerPage.closeZoom,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.none,
                ),
              ),
              children: [
                const OsmTileLayer(),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: center,
                      width: 40,
                      height: 40,
                      alignment: Alignment.topCenter,
                      child: Icon(
                        Icons.location_on,
                        size: 40,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const OsmAttribution(),
              ],
            ),
            // Top right, so the map credit along the bottom stays readable.
            Positioned(
              right: 12,
              top: 8,
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  backgroundColor: theme.colorScheme.surfaceContainerLowest,
                  foregroundColor: theme.colorScheme.onSurface,
                ),
                onPressed: onChange,
                icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
                label: const Text('Change'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A short line under a section, such as what Save found missing.
class _Note extends StatelessWidget {
  const _Note({required this.text, this.error = false, super.key});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = error
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Icon(
            error ? Icons.error_outline : Icons.info_outline,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// The one primary action, always in reach of the thumb.
class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.label,
    required this.saving,
    required this.onSave,
  });

  final String label;
  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton(
          onPressed: saving ? null : onSave,
          child: AnimatedSwitcher(
            duration: Motion.of(context, Motion.short),
            child: saving
                ? const SizedBox.square(
                    key: ValueKey('saving'),
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(label, key: const ValueKey('label')),
          ),
        ),
      ),
    );
  }
}
