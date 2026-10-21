import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:lanka_radar/core/data/database.dart';
import 'package:lanka_radar/core/data/phone_sources.dart';
import 'package:path_provider/path_provider.dart';

/// A PDF that couldn't be downloaded, or wasn't a PDF.
class PdfException implements Exception {
  const PdfException(this.message);

  final String message;

  @override
  String toString() => 'PdfException: $message';
}

/// The official PDFs, kept on the phone once opened so they open again
/// offline. Past [limit] bytes the PDFs opened longest ago go first; a saved
/// one stays until it is unsaved.
class PdfStore {
  PdfStore({
    required AppDatabase database,
    http.Client? client,
    Future<Directory> Function()? folder,
    DateTime Function()? now,
    this.limit = 200 * 1024 * 1024,
  }) : _db = database,
       _client = client ?? http.Client(),
       _folder = folder ?? _defaultFolder,
       _now = now ?? DateTime.now;

  final AppDatabase _db;
  final http.Client _client;
  final Future<Directory> Function() _folder;
  final DateTime Function() _now;
  final int limit;

  static Future<Directory> _defaultFolder() async =>
      Directory('${(await getApplicationSupportDirectory()).path}/pdfs');

  /// The kept PDFs, the last opened first.
  Stream<List<PdfRow>> watch() => _db.watchPdfs();

  /// The PDF at [url] on the phone: the copy kept, or downloaded now and kept.
  Future<File> open(String url, {required String title}) async {
    final folder = await _folder();
    final known = await _db.pdf(url);
    if (known != null) {
      final file = File('${folder.path}/${known.file}');
      if (file.existsSync()) {
        await _db.savePdf(known.copyWith(openedAt: _now()));
        return file;
      }
    }
    final http.Response response;
    try {
      response = await _client
          .get(Uri.parse(url), headers: {'User-Agent': userAgent})
          .timeout(const Duration(minutes: 2));
    } on Exception catch (error) {
      throw PdfException("Couldn't download it ($error)");
    }
    final bytes = response.bodyBytes;
    if (response.statusCode != 200 || !_isPdf(bytes)) {
      throw PdfException("Couldn't download it (${response.statusCode})");
    }
    final name = '${fileName(url)}.pdf';
    final file = File('${folder.path}/$name');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    await _db.savePdf(
      PdfRow(
        url: url,
        file: name,
        title: title,
        bytes: bytes.length,
        openedAt: _now(),
        saved: known?.saved ?? false,
      ),
    );
    await _trim(folder);
    return file;
  }

  Future<bool> isSaved(String url) async =>
      (await _db.pdf(url))?.saved ?? false;

  Future<void> setSaved(String url, {required bool saved}) async {
    final known = await _db.pdf(url);
    if (known != null) {
      await _db.savePdf(known.copyWith(saved: saved));
    }
  }

  /// Removes every kept PDF that isn't saved.
  Future<void> clear() async {
    final folder = await _folder();
    for (final row in await _db.allPdfs()) {
      if (!row.saved) {
        await _remove(folder, row);
      }
    }
  }

  /// Drops the PDFs opened longest ago, saved ones aside, until the rest fit
  /// in [limit].
  Future<void> _trim(Directory folder) async {
    final rows = await _db.allPdfs();
    var total = rows.fold<int>(0, (sum, row) => sum + row.bytes);
    for (final row in rows.reversed) {
      if (total <= limit) {
        break;
      }
      if (!row.saved) {
        await _remove(folder, row);
        total -= row.bytes;
      }
    }
  }

  Future<void> _remove(Directory folder, PdfRow row) async {
    final file = File('${folder.path}/${row.file}');
    if (file.existsSync()) {
      await file.delete();
    }
    await _db.deletePdf(row.url);
  }

  static bool _isPdf(Uint8List bytes) =>
      bytes.length > 4 &&
      bytes[0] == 0x25 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x44 &&
      bytes[3] == 0x46;

  /// A file name that stays the same for [url]: 64-bit FNV-1a, in hex.
  static String fileName(String url) {
    var hash = 0xcbf29ce484222325;
    for (final unit in url.codeUnits) {
      hash = (hash ^ unit) * 0x100000001b3;
    }
    return hash.toUnsigned(64).toRadixString(16).padLeft(16, '0');
  }
}
