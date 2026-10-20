import 'package:share_plus/share_plus.dart';

/// Shares plain text through the phone's share sheet. The app provides one,
/// so tests can see what would be shared.
class Sharing {
  const Sharing();

  Future<void> share(String text) async {
    await SharePlus.instance.share(ShareParams(text: text));
  }
}
