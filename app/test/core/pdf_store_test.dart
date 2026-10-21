import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lanka_radar/core/data/database.dart';
import 'package:lanka_radar/core/pdf_store.dart';

import '../helpers/fake_branch.dart';

/// A PDF of [size] bytes: the header, then padding.
Uint8List pdf(int size) => Uint8List(size)..setAll(0, '%PDF-1.7'.codeUnits);

void main() {
  late AppDatabase database;
  late Directory folder;
  late List<String> downloads;
  late Map<String, http.Response Function()> served;
  late DateTime now;

  setUp(() {
    database = memoryDatabase();
    folder = Directory.systemTemp.createTempSync('lanka-radar-pdfs');
    downloads = [];
    served = {};
    now = DateTime(2026, 10, 21, 9);
  });

  tearDown(() async {
    await database.close();
    folder.deleteSync(recursive: true);
  });

  PdfStore store({int limit = 1000}) => PdfStore(
    database: database,
    client: MockClient((request) async {
      downloads.add(request.url.toString());
      return served[request.url.toString()]?.call() ??
          http.Response('Not found', 404);
    }),
    folder: () async => folder,
    now: () => now,
    limit: limit,
  );

  void serve(String url, int size) =>
      served[url] = () => http.Response.bytes(pdf(size), 200);

  test('a PDF is downloaded once, then opens from the phone', () async {
    serve('https://a.pdf', 300);

    final first = await store().open('https://a.pdf', title: 'A gazette');
    now = now.add(const Duration(hours: 1));
    served.clear();
    final again = await store().open('https://a.pdf', title: 'A gazette');

    expect(downloads, ['https://a.pdf']);
    expect(again.path, first.path);
    expect(again.lengthSync(), 300);
    final row = (await database.allPdfs()).single;
    expect((row.title, row.bytes, row.openedAt), ('A gazette', 300, now));
  });

  test('what is not a PDF, or not there, is not kept', () async {
    served['https://page.pdf'] = () => http.Response('<html>', 200);

    await expectLater(
      store().open('https://page.pdf', title: 'x'),
      throwsA(isA<PdfException>()),
    );
    await expectLater(
      store().open('https://gone.pdf', title: 'x'),
      throwsA(isA<PdfException>()),
    );
    expect(await database.allPdfs(), isEmpty);
  });

  test(
    'past the limit the PDFs opened longest ago go, saved ones stay',
    () async {
      for (final name in ['a', 'b', 'c', 'd']) {
        serve('https://$name.pdf', 400);
      }
      final pdfs = store();
      await pdfs.open('https://a.pdf', title: 'a');
      await pdfs.setSaved('https://a.pdf', saved: true);
      now = now.add(const Duration(minutes: 1));
      await pdfs.open('https://b.pdf', title: 'b');
      now = now.add(const Duration(minutes: 1));
      await pdfs.open('https://c.pdf', title: 'c');
      now = now.add(const Duration(minutes: 1));
      await pdfs.open('https://d.pdf', title: 'd');

      final kept = [for (final row in await database.allPdfs()) row.title];
      expect(kept, ['d', 'a']);
      expect(folder.listSync(), hasLength(2));
    },
  );

  test('clearing keeps the saved ones', () async {
    serve('https://a.pdf', 100);
    serve('https://b.pdf', 100);
    final pdfs = store();
    await pdfs.open('https://a.pdf', title: 'a');
    await pdfs.open('https://b.pdf', title: 'b');
    await pdfs.setSaved('https://b.pdf', saved: true);

    await pdfs.clear();

    expect([for (final row in await database.allPdfs()) row.title], ['b']);
    expect(await pdfs.isSaved('https://b.pdf'), isTrue);
    expect(folder.listSync(), hasLength(1));
  });

  test("a file's name stays the same for its link", () {
    expect(
      PdfStore.fileName('https://a.pdf'),
      PdfStore.fileName('https://a.pdf'),
    );
    expect(
      PdfStore.fileName('https://a.pdf'),
      isNot(PdfStore.fileName('https://b.pdf')),
    );
    expect(PdfStore.fileName('https://a.pdf'), hasLength(16));
  });
}
