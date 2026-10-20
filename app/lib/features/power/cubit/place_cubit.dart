import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lanka_radar/core/data/now_repository.dart';
import 'package:lanka_radar/core/data/power_cuts.dart';
import 'package:lanka_radar/core/location.dart';

final class PlaceState extends Equatable {
  const PlaceState({
    required this.draft,
    this.original,
    this.provinces,
    this.areas = const {},
    this.regionsFailed = false,
    this.locating = false,
    this.failure,
    this.attempts = 0,
  });

  /// The place as edited so far; kept only on Save.
  final Place draft;

  /// The place as saved; null for a new one.
  final Place? original;

  /// CEB's provinces, and the areas of each province asked for; null and
  /// missing until EDLCare answers.
  final List<CebRegion>? provinces;
  final Map<String, List<CebRegion>> areas;

  /// EDLCare didn't answer for the lists.
  final bool regionsFailed;
  final bool locating;

  /// Why the last "Use my location" didn't work.
  final LocateFailure? failure;

  /// Save presses that found something missing; after one, what is missing
  /// is pointed out where it belongs.
  final int attempts;

  bool get isNew => original == null;

  bool get showErrors => attempts > 0;

  String? get nameError =>
      showErrors && draft.name.trim().isEmpty ? 'Give it a name' : null;

  String? get areaError =>
      showErrors && draft.area == null ? 'Pick its CEB area' : null;

  String? get pointError =>
      showErrors && draft.point == null ? 'Set where it is' : null;

  bool get changed => draft != original;

  /// What the place still needs before it can be saved.
  String? get missing => draft.name.trim().isEmpty
      ? 'Give it a name'
      : draft.area == null
      ? 'Pick its CEB area'
      : draft.point == null
      ? 'Set its location'
      : null;

  bool get canSave => missing == null && changed;

  /// The areas of the draft's province; null while unknown.
  List<CebRegion>? get provinceAreas =>
      draft.province == null ? null : areas[draft.province!.id];

  PlaceState copyWith({
    Place? draft,
    List<CebRegion>? Function()? provinces,
    Map<String, List<CebRegion>>? areas,
    bool? regionsFailed,
    bool? locating,
    LocateFailure? Function()? failure,
    int? attempts,
  }) => PlaceState(
    draft: draft ?? this.draft,
    original: original,
    provinces: provinces != null ? provinces() : this.provinces,
    areas: areas ?? this.areas,
    regionsFailed: regionsFailed ?? this.regionsFailed,
    locating: locating ?? this.locating,
    failure: failure != null ? failure() : this.failure,
    attempts: attempts ?? this.attempts,
  );

  @override
  List<Object?> get props => [
    draft,
    original,
    provinces,
    areas,
    regionsFailed,
    locating,
    failure,
    attempts,
  ];
}

/// One place being added or changed, kept as a draft until saved.
class PlaceCubit extends Cubit<PlaceState> {
  PlaceCubit(this._phone, this._locate, Place place, {required bool isNew})
    : super(PlaceState(draft: place, original: isNew ? null : place));

  final NowRepository _phone;
  final Locate _locate;

  /// The draft as it should be saved.
  Place get result => state.draft.copyWith(name: state.draft.name.trim());

  /// The place to save, or null when something is missing (and then it is
  /// pointed out).
  Place? trySave() {
    if (state.missing != null) {
      emit(state.copyWith(attempts: state.attempts + 1));
      return null;
    }
    return result;
  }

  /// Reads CEB's provinces, and the areas of the place's province.
  Future<void> loadRegions() async {
    emit(state.copyWith(regionsFailed: false));
    try {
      final provinces = state.provinces ?? await _phone.powerProvinces();
      if (isClosed) {
        return;
      }
      emit(state.copyWith(provinces: () => provinces));
      if (state.draft.province case final province?) {
        await _loadAreas(province);
      }
    } on Exception {
      if (!isClosed) {
        emit(state.copyWith(regionsFailed: true));
      }
    }
  }

  void rename(String name) =>
      emit(state.copyWith(draft: state.draft.copyWith(name: name)));

  Future<void> pickProvince(CebRegion province) async {
    if (province == state.draft.province) {
      return;
    }
    emit(
      state.copyWith(
        draft: state.draft.copyWith(province: () => province, area: () => null),
      ),
    );
    try {
      await _loadAreas(province);
    } on Exception {
      if (!isClosed) {
        emit(state.copyWith(regionsFailed: true));
      }
    }
  }

  void pickArea(CebRegion area) =>
      emit(state.copyWith(draft: state.draft.copyWith(area: () => area)));

  void setPoint(GeoPoint point) => emit(
    state.copyWith(
      draft: state.draft.copyWith(point: () => point),
      failure: () => null,
    ),
  );

  /// Sets the place where the phone is now.
  Future<void> locate() async {
    emit(state.copyWith(locating: true, failure: () => null));
    try {
      final point = await _locate();
      if (!isClosed) {
        emit(
          state.copyWith(
            draft: state.draft.copyWith(point: () => point),
            locating: false,
          ),
        );
      }
    } on LocateException catch (error) {
      if (!isClosed) {
        emit(state.copyWith(locating: false, failure: () => error.failure));
      }
    }
  }

  Future<void> _loadAreas(CebRegion province) async {
    if (state.areas.containsKey(province.id)) {
      return;
    }
    final areas = await _phone.powerAreas(province.id);
    if (!isClosed) {
      emit(state.copyWith(areas: {...state.areas, province.id: areas}));
    }
  }
}
