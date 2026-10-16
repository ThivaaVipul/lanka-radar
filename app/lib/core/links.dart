import 'package:url_launcher/url_launcher.dart';

/// Opens a link outside the app: PDFs and pages go to the phone's browser or
/// PDF app. False when nothing could open it.
typedef OpenLink = Future<bool> Function(Uri link);

Future<bool> openExternally(Uri link) =>
    launchUrl(link, mode: LaunchMode.externalApplication);
