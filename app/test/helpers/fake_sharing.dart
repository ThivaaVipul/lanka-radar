import 'package:lanka_radar/core/sharing.dart';

/// Keeps what would have been shared.
class FakeSharing extends Sharing {
  final shared = <String>[];
  final files = <String>[];

  @override
  Future<void> share(String text) async => shared.add(text);

  @override
  Future<void> shareFile(String path, {required String title}) async =>
      files.add(path);
}
