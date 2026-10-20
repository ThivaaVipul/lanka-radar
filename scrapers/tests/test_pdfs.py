import json
from collections.abc import Callable
from typing import Any

import pytest
from tamil.txt2unicode import bamini2unicode

from lanka_radar import pdfs
from lanka_radar.items import KeyNumber
from lanka_radar.pdfs import Line

EXPECTED = "expected_titles.json"
# Tamil letters built from code points, so this file stays plain ASCII.
TAMIL = chr(0x0B9A) + chr(0x0BC1) + chr(0x0B99) + chr(0x0BCD) + chr(0x0B95)
KA, TTA, TA, PA = chr(0x0B95), chr(0x0B9F), chr(0x0BA4), chr(0x0BAA)
RA, SA = chr(0x0BB0), chr(0x0BB8)
AA_SIGN, I_SIGN, II_SIGN, U_SIGN = chr(0x0BBE), chr(0x0BBF), chr(0x0BC0), chr(0x0BC1)
UU_SIGN, E_SIGN, EE_SIGN, OO_SIGN = chr(0x0BC2), chr(0x0BC6), chr(0x0BC7), chr(0x0BCB)
VIRAMA = chr(0x0BCD)

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


def glyphs(text: str, x: float = 0.0) -> list[dict[str, Any]]:
    """Arial Unicode MS characters read from their glyph IDs, in drawing order."""
    return [{**char, "glyph": True} for char in chars(text, "ArialUnicodeMS", x)]


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


@pytest.mark.parametrize(
    "name",
    [
        "gazette-2509-59-ta.pdf",  # an election notice: ra drawn as aa, bold drawn as outline
        "gazette-2508-31-ta.pdf",  # an outline copy set 4 points off its filled text
        "gazette-2509-31-ta.pdf",  # a direction number printed above the title
    ],
)
def test_reads_arial_unicode_tamil_from_the_glyph_ids(
    name: str, fixture_bytes: Callable[[str], bytes]
) -> None:
    reading = pdfs.read(fixture_bytes(name), tamil=True)

    assert reading.title == json.loads(fixture_bytes(EXPECTED))[name]


def test_arial_unicode_glyph_ids_map_to_tamil() -> None:
    assert pdfs.ARIAL_TAMIL[1819] == KA
    assert pdfs.ARIAL_TAMIL[1841] == AA_SIGN
    assert pdfs.ARIAL_TAMIL[1865] == chr(0x0BF2)  # the last of Unicode 3.0's Tamil
    assert pdfs.ARIAL_TAMIL[8065] == KA + U_SIGN
    assert pdfs.ARIAL_TAMIL[8077] == TTA + UU_SIGN
    assert pdfs.ARIAL_TAMIL[8088] == PA + UU_SIGN
    assert pdfs.ARIAL_TAMIL[8111] == SA + VIRAMA + RA + II_SIGN
    assert pdfs.ARIAL_TAMIL[8132] == SA + VIRAMA


def test_glyphs_found_in_2026_gazettes_map_to_what_their_pages_print() -> None:
    # Each was read off the printed title it held back (Thunukkai, Mutur, Eravur, ...).
    found = {
        8064: "KA VIRAMA SSA",  # thakshina
        8078: "NNA U",  # thunukkaai
        8081: "TA UU",  # muuthuur
        8083: "NA UU",  # nuurumukammathu
        8091: "YA II",  # kuriyiittai
        8101: "LA UU",  # luuks
        8108: "VA UU",  # eraavuur
        8110: "SA II",  # asiis
        8133: "HA VIRAMA",  # abdullaah
    }
    for glyph, names in found.items():
        assert pdfs.ARIAL_TAMIL[glyph] == pdfs._tamil(names)


def test_an_unknown_glyph_keeps_the_tamil_title_out_and_is_reported(
    fixture_bytes: Callable[[str], bytes], monkeypatch: pytest.MonkeyPatch
) -> None:
    # Ku (glyph 8065) is in the title's "vadakku"; pretend the table doesn't know it.
    monkeypatch.delitem(pdfs.ARIAL_TAMIL, 8065)

    reading = pdfs.read(fixture_bytes("gazette-2509-59-ta.pdf"), tamil=True)

    assert reading.title is None
    assert reading.unknown == (8065,)


def test_glyphs_are_put_in_reading_order() -> None:
    # The e and ee signs are drawn before their letter, and ra before i with the aa glyph.
    row = glyphs(E_SIGN + TA + AA_SIGN + I_SIGN) + glyphs(EE_SIGN + KA + AA_SIGN, x=40.0)

    [line] = pdfs.lines_of(row)

    assert line.text == TA + E_SIGN + RA + I_SIGN + " " + KA + OO_SIGN
    assert line.trusted


def test_glyphs_that_make_no_tamil_word_are_not_trusted() -> None:
    [line] = pdfs.lines_of(glyphs(I_SIGN + KA))

    assert not line.trusted


def test_an_outline_copy_marks_the_line_bold_and_is_not_read() -> None:
    filled = chars("Filling of a Vacancy", "ArialUnicodeMS")
    outline = [
        {**char, "x0": char["x0"] + 3.9, "x1": char["x1"] + 3.9, "outline": True} for char in filled
    ]

    [line] = pdfs.lines_of(filled + outline)

    assert line.text == "Filling of a Vacancy"
    assert line.bold


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


def test_tamil_from_a_text_map_is_not_trusted() -> None:
    # Only Bamini fonts and Arial Unicode MS glyph IDs give Tamil that can be trusted.
    [latha] = pdfs.lines_of(chars(TAMIL, "Latha"))
    [arial] = pdfs.lines_of(chars(TAMIL, "ArialUnicodeMS"))

    assert not latha.trusted
    assert not arial.trusted


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


def test_title_stops_at_a_bold_paragraph_set_smaller() -> None:
    paragraph = (
        "Mrs. M. J. Beebi, a member of the Kalpitiya Pradeshiya Sabha, has ceased to be a member"
    )
    lines = [
        *MASTHEAD,
        Line("NOTICE UNDER SECTION 10A(1)(a)", 11.0, True),
        Line(paragraph, 10.0, True),
        *BODY * 3,
    ]

    assert pdfs.title(lines, tamil=False) == "NOTICE UNDER SECTION 10A(1)(a)"


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


def test_price_labels_drop_latin_names_and_keep_the_net_weight() -> None:
    # Gazette 2504/86 (CAA, canned fish), as pdfplumber reads its table; "l55g" is printed.
    pack = "Net weight of {}g and\ndrained weight of {}g or\nabove"
    table = [
        ["Canned Fish Type", "Weight (Gram)", "Maximum Retail Price\n(Per Can)"],
        [
            "Tuna ( Katsuwonus pelamis , Auxis rochei,\nEuthynnus affinis and Auxis thazard)",
            pack.format("155", "105"),
            "Rs. 220/-",
        ],
        [None, pack.format("425", "280"), "Rs. 510/-"],
        [
            "Mackerel (Scomber scombrus, Scomber japonicus\nand Scomber australasicus)",
            pack.format("l55", "105"),
            "Rs. 240/-",
        ],
    ]

    assert pdfs.price_numbers([table]) == [
        KeyNumber("Tuna 155g", 220.0, "LKR"),
        KeyNumber("Tuna 425g", 510.0, "LKR"),
        KeyNumber("Mackerel 155g", 240.0, "LKR"),
    ]


def test_prices_with_thousands_separators() -> None:
    table = [["Item", "Maximum Retail Price"], ["Cement 50kg", "Rs. 2,150.00"]]

    assert pdfs.price_numbers([table]) == [KeyNumber("Cement 50kg", 2150.0, "LKR")]


def test_tables_without_a_price_column_are_ignored() -> None:
    assert pdfs.price_numbers([[["Name", "Date"], ["A", "2026"]]]) == []
