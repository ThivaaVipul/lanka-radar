import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lanka_radar/core/data/health.dart';
import 'package:lanka_radar/core/data/now_repository.dart';

/// The Sources screen: every source's health, as last recorded. Null until
/// loaded.
class SourcesCubit extends Cubit<Health?> {
  SourcesCubit(this._phone) : super(null);

  final NowRepository _phone;

  Future<void> load() async {
    final health = await _phone.health();
    if (!isClosed) {
      emit(health);
    }
  }
}
