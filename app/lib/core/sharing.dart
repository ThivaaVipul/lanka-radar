import 'package:share_plus/share_plus.dart';

/// Shares plain text, or a file, through the phone's share sheet. The app
/// provides one, so tests can see what would be shared.
class Sharing {
  const Sharing();

  Future<void> share(String text) async {
    await SharePlus.instance.share(ShareParams(text: text));
  }

  /// A PDF kept on the phone, [title] as what it is.
  Future<void> shareFile(String path, {required String title}) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: 'application/pdf')],
        subject: title,
      ),
    );
  }
}
