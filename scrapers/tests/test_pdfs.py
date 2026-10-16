import json
from collections.abc import Callable
from typing import Any

from tamil.txt2unicode import bamini2unicode

from lanka_radar import pdfs
from lanka_radar.items import KeyNumber
from lanka_radar.pdfs import Line

EXPECTED = "expected_titles.json"
# Tamil letters built from code points, so this file stays plain ASCII.
TAMIL = chr(0x0B9A) + chr(0x0BC1) + chr(0x0B99) + chr(0x0BCD) + chr(0x0B95)

MASTHEAD = [
    Line("The Gazette of the Democratic Socialist Republic of Sri Lanka", 36.0, True),
    Line("EXTRAORDINARY", 14.0, True),
    Line("No. 2510/01 - MONDAY, OCTOBER 12, 2026", 10.0, False),
    Line("PART I : SECTION (I) - GENERAL", 18.0, True),
    Line("Government Notifications", 16.0, True),
]
BODY = [
    Line(
        "IT is hereby notified that by virtue of powers vested in me under Section 17", 10.0, False
    )
]


def chars(text: str, font: str, x: float = 0.0, size: float = 10.0) -> list[dict[str, Any]]:
    """Characters as pdfplumber gives them, side by side on one line."""
    return [
        {
            "text": char,
            "fontname": f"ABCDEF+{font}",
            "size": size,
            "top": 100.0,
            "x0": x + index * 5.0,
            "x1": x + index * 5.0 + 5.0,
        }
        for index, char in enumerate(text)
    ]


def test_reads_the_english_title_and_the_fuel_prices(fixture_bytes: Callable[[str], bytes]) -> None:
    reading = pdfs.read(fixture_bytes("gazette-2504-03-en.pdf"), tamil=False)

    assert reading.title == json.loads(fixture_bytes(EXPECTED))["gazette-2504-03-en.pdf"]
    assert reading.numbers == [
        KeyNumber("Lanka Petrol 92 Octane", 399.0, "LKR", 414.0),
        KeyNumber("Lanka Petrol 95 Octane Euro 4", 475.0, "LKR", 495.0),
    ]


def test_reads_the_tamil_title_from_a_bamini_font(fixture_bytes: Callable[[str], bytes]) -> None:
    reading = pdfs.read(fixture_bytes("gazette-2504-03-ta.pdf"), tamil=True)

    assert reading.title == json.loads(fixture_bytes(EXPECTED))["gazette-2504-03-ta.pdf"]
    assert reading.numbers == []


def test_bamini_runs_are_converted_and_latin_runs_kept_as_they_are() -> None:
    row = chars("rl;lk;", "GP-RasanjiReular") + chars("(a)", "TimesNewRomanPSMT", x=30.0)

    [line] = pdfs.lines_of(row)

    assert line.text == bamini2unicode("rl;lk;") + "(a)"
    assert line.trusted


def test_a_word_sized_gap_between_runs_is_a_space() -> None:
    row = chars("ACT,", "TimesNewRomanPS-BoldMT") + chars("No.", "TimesNewRomanPSMT", x=40.0)

    assert [line.text for line in pdfs.lines_of(row)] == ["ACT, No."]


def test_sinhala_runs_are_dropped() -> None:
    row = chars("Y%S", "FMAbabldBold") + chars("EXTRAORDINARY", "TimesNewRomanPS-BoldMT", x=40.0)

    assert [line.text for line in pdfs.lines_of(row)] == ["EXTRAORDINARY"]


def test_unicode_tamil_from_another_font_is_not_trusted() -> None:
    [line] = pdfs.lines_of(chars(TAMIL, "ArialUnicodeMS"))

    assert not line.trusted


def test_title_is_the_block_after_the_masthead() -> None:
    lines = [
        *MASTHEAD,
        Line("DGC/A877/PL305.", 10.0, False),
        Line("CUSTOMS NOTIFICATION (GENERAL)", 10.0, True),
        Line("Customs Ordinance (Chapter 235)", 10.0, True),
        Line("RATES OF EXCHANGE", 10.0, False),
        *BODY * 3,
    ]

    assert pdfs.title(lines, tamil=False) == (
        "CUSTOMS NOTIFICATION (GENERAL) Customs Ordinance (Chapter 235) RATES OF EXCHANGE"
    )


def test_title_skips_an_order_number() -> None:
    lines = [
        *MASTHEAD,
        Line("Order No.: 97", 10.0, True),
        Line("CONSUMER AFFAIRS AUTHORITY ACT, NO 9 OF 2003", 11.0, True),
        *BODY * 3,
    ]

    assert pdfs.title(lines, tamil=False) == "CONSUMER AFFAIRS AUTHORITY ACT, NO 9 OF 2003"


def test_no_title_without_a_masthead() -> None:
    assert pdfs.title(BODY * 3, tamil=False) is None


def test_a_tamil_title_needs_trusted_tamil() -> None:
    trusted = [*MASTHEAD, Line(TAMIL, 11.0, True), *BODY * 3]
    scrambled = [*MASTHEAD, Line(TAMIL, 11.0, True, trusted=False), *BODY * 3]
    english = [*MASTHEAD, Line("CUSTOMS NOTIFICATION", 11.0, True), *BODY * 3]

    assert pdfs.title(trusted, tamil=True) == TAMIL
    assert pdfs.title(scrambled, tamil=True) is None
    assert pdfs.title(english, tamil=True) is None


def test_maximum_prices_carry_the_item_down_to_its_other_sizes() -> None:
    table = [
        ["Canned Fish Type", "Weight (Gram)", "Maximum Retail Price (Per Can)"],
        ["Tuna", "155g", "Rs. 220/-"],
        ["", "425g", "Rs. 510/-"],
    ]

    assert pdfs.price_numbers([table]) == [
        KeyNumber("Tuna 155g", 220.0, "LKR"),
        KeyNumber("Tuna 425g", 510.0, "LKR"),
    ]


def test_a_revision_keeps_the_current_price_as_the_one_before() -> None:
    table = [
        ["Type of Fuel", "Current Price (1 liter)", "Revise Price (1 liter)"],
        ["Lanka Petrol 92 Octane", "Rs. 414.00", "Rs. 399.00"],
    ]

    assert pdfs.price_numbers([table]) == [KeyNumber("Lanka Petrol 92 Octane", 399.0, "LKR", 414.0)]


def test_prices_with_thousands_separators() -> None:
    table = [["Item", "Maximum Retail Price"], ["Cement 50kg", "Rs. 2,150.00"]]

    assert pdfs.price_numbers([table]) == [KeyNumber("Cement 50kg", 2150.0, "LKR")]


def test_tables_without_a_price_column_are_ignored() -> None:
    assert pdfs.price_numbers([[["Name", "Date"], ["A", "2026"]]]) == []
