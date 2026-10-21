"""Sri Lanka's 25 districts, as the LP gas price lists name them (each in its own way)."""

from __future__ import annotations

import difflib

DISTRICTS = (
    "Ampara",
    "Anuradhapura",
    "Badulla",
    "Batticaloa",
    "Colombo",
    "Galle",
    "Gampaha",
    "Hambantota",
    "Jaffna",
    "Kalutara",
    "Kandy",
    "Kegalle",
    "Kilinochchi",
    "Kurunegala",
    "Mannar",
    "Matale",
    "Matara",
    "Monaragala",
    "Mullaitivu",
    "Nuwara Eliya",
    "Polonnaruwa",
    "Puttalam",
    "Ratnapura",
    "Trincomalee",
    "Vavuniya",
)

# Spellings too far from the usual ones to be matched: Litro's Mulative, N Eliya and
# Vauniya, Laugfs's Nuwaraeliya.
_ALIASES = {
    "mulative": "Mullaitivu",
    "n eliya": "Nuwara Eliya",
    "nuwaraeliya": "Nuwara Eliya",
    "vauniya": "Vavuniya",
}


def district(name: str) -> str | None:
    """The district a price list's name means, or None when it is none of them."""
    name = " ".join(name.lower().split())
    if name in _ALIASES:
        return _ALIASES[name]
    lowered = {district.lower(): district for district in DISTRICTS}
    match = difflib.get_close_matches(name, list(lowered), n=1, cutoff=0.75)
    return lowered[match[0]] if match else None
