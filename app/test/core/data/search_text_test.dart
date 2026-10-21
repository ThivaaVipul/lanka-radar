import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/data/search_text.dart';

FeedItem headed(String headline) => FeedItem(
  id: 'x',
  source: 'exams',
  topic: 'exams',
  headlineEn: headline,
  published: DateTime(2026, 10),
);

void main() {
  test('school exams are found by their short names', () {
    expect(
      searchText(headed('G.C.E. (Ordinary Level) Examination 2026')),
      contains('o/l'),
    );
    expect(
      searchText(headed('G.C.E. (Advanced Level) Examination')),
      contains('a/l'),
    );
    expect(
      searchText(headed('Grade 5 Scholarship Examination')),
      contains('scholarship'),
    );
  });

  test('recruitments are jobs, council vacancies are not', () {
    expect(
      searchText(headed('Recruitment to the Posts of Legal Officer')),
      contains('job'),
    );
    expect(
      searchText(headed('Filling of a Vacancy in Udapalatha Pradeshiya Sabha')),
      isNot(contains('job')),
    );
  });

  test('an alias needs its whole word', () {
    expect(searchText(headed('USD/LKR up 2.1% in a week')), contains('dollar'));
    expect(
      searchText(headed('Housing Development')),
      isNot(contains('dollar')),
    );
  });
  group('a line around what search found', () {
    const text =
        'GAZETTE EXTRAORDINARY Customs Ordinance (Chapter 235) ORDER UNDER '
        'SECTION 10A. By virtue of the powers vested in me, the import of '
        'Kilinochchi rice is exempted from the special commodity levy until '
        'the end of the year.';

    test('cuts at spaces around the first word found, with dots', () {
      expect(
        lineAround(text, ['kilinochchi']),
        '...the powers vested in me, the import of Kilinochchi rice is exempted '
        'from the special commodity levy until the end of the year.',
      );
    });

    test('starts at the start, finds words from their start only', () {
      expect(lineAround(text, ['gazette'])!.startsWith('GAZETTE'), isTrue);
      expect(lineAround(text, ['rice'])!.contains('Kilinochchi rice'), isTrue);
      expect(lineAround('Price list', ['rice']), isNull);
    });
  });
}
