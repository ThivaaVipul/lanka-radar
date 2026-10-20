import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lanka_radar/core/data/now_repository.dart';
import 'package:lanka_radar/core/data/power_cuts.dart';

/// How the last look for power cuts went.
enum PowerCheck { idle, checking, done, failed }

final class PowerState extends Equatable {
  const PowerState({this.setup, this.power, this.check = PowerCheck.idle});

  /// Null until read.
  final PowerSetup? setup;

  /// The cuts at each place as last read.
  final PowerNow? power;
  final PowerCheck check;

  /// The cuts at [place], or null when its area hasn't been read yet.
  List<Outage>? cutsAt(Place place) {
    for (final cuts in power?.places ?? const <PlaceCuts>[]) {
      if (cuts.place.id == place.id) {
        return cuts.outages;
      }
    }
    return null;
  }

  PowerState copyWith({
    PowerSetup? setup,
    PowerNow? Function()? power,
    PowerCheck? check,
  }) => PowerState(
    setup: setup ?? this.setup,
    power: power != null ? power() : this.power,
    check: check ?? this.check,
  );

  @override
  List<Object?> get props => [setup, power, check];
}

/// The Power tab: the places watched and the cuts at them.
class PowerCubit extends Cubit<PowerState> {
  PowerCubit(this._phone, {DateTime Function()? now})
    : _now = now ?? DateTime.now,
      super(const PowerState());

  /// Showing the tab again looks again once the last look is this old.
  static const lookAgain = Duration(minutes: 2);

  final NowRepository _phone;
  final DateTime Function() _now;
  DateTime? _looked;

  /// Shows the places and the cuts last read, then looks again unless it
  /// looked a moment ago.
  Future<void> show() async {
    final setup = await _phone.powerSetup();
    final power = await _phone.powerNow();
    if (isClosed) {
      return;
    }
    emit(state.copyWith(setup: setup, power: () => power));
    final looked = _looked;
    if (looked == null || _now().difference(looked) >= lookAgain) {
      await check();
    }
  }

  /// Reads each place's area again and shows the cuts at each place.
  Future<void> check() async {
    if (state.setup?.ready.isEmpty ?? true) {
      return;
    }
    _looked = _now();
    emit(state.copyWith(check: PowerCheck.checking));
    await _phone.refreshPower();
    final power = await _phone.powerNow();
    final status = await _phone.status(NowRepository.powerSource);
    if (!isClosed) {
      emit(
        state.copyWith(
          power: () => power,
          check: status.lastError == null ? PowerCheck.done : PowerCheck.failed,
        ),
      );
    }
  }

  /// A new place's ID.
  String newId() => 'place-${_now().microsecondsSinceEpoch}';

  /// The name a new place starts with: Home, then Work, then "Place 3".
  String newName() {
    final taken = {for (final place in _setup.places) place.name};
    for (final name in const ['Home', 'Work']) {
      if (!taken.contains(name)) {
        return name;
      }
    }
    return 'Place ${_setup.places.length + 1}';
  }

  /// Keeps [place], new or changed, then looks for cuts at it (in the
  /// background, so its page can close).
  Future<void> save(Place place) async {
    await _save(_setup.withPlace(place));
    unawaited(check());
  }

  /// Stops watching a place; gives where it was, so it can be put back.
  Future<int> remove(String id) async {
    final index = _setup.places.indexWhere((place) => place.id == id);
    await _save(_setup.without(id));
    await _showStored();
    return index;
  }

  /// Puts a removed place back.
  Future<void> restore(Place place, int index) async {
    await _save(_setup.inserted(place, index));
    await _showStored();
  }

  PowerSetup get _setup => state.setup ?? const PowerSetup();

  Future<void> _showStored() async {
    final power = await _phone.powerNow();
    if (!isClosed) {
      emit(state.copyWith(power: () => power));
    }
  }

  Future<void> _save(PowerSetup setup) async {
    await _phone.savePowerSetup(setup);
    if (!isClosed) {
      emit(state.copyWith(setup: setup));
    }
  }
}
