"""The feed item the app reads, and its JSON form."""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from dataclasses import dataclass, field
from datetime import date
from typing import Any

TOPICS = ("prices", "gazettes", "rates", "holidays", "exams", "jobs")

_MONTHS = ("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")


def short_date(day: date) -> str:
    """Formats a day like 30 Sep 2026, the same on every machine whatever its locale."""
    return f"{day.day} {_MONTHS[day.month - 1]} {day.year}"


@dataclass(frozen=True)
class KeyNumber:
    label: str
    value: float
    unit: str
    previous: float | None = None

    def to_json(self) -> dict[str, Any]:
        data: dict[str, Any] = {"label": self.label, "value": self.value, "unit": self.unit}
        if self.previous is not None:
            data["previous"] = self.previous
        return data


@dataclass(frozen=True)
class Item:
    id: str
    source: str
    topic: str
    headline_en: str
    published: date
    headline_ta: str | None = None
    issuer: str | None = None
    effective: date | None = None
    links: Mapping[str, str] = field(default_factory=dict)
    key_numbers: Sequence[KeyNumber] = ()
    data: Mapping[str, Any] = field(default_factory=dict)
    alert: bool = False

    def __post_init__(self) -> None:
        if self.topic not in TOPICS:
            raise ValueError(f"unknown topic {self.topic!r}")

    def to_json(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "source": self.source,
            "topic": self.topic,
            "issuer": self.issuer,
            "headline": {"en": self.headline_en, "ta": self.headline_ta},
            "keyNumbers": [number.to_json() for number in self.key_numbers],
            "published": self.published.isoformat(),
            "effective": self.effective.isoformat() if self.effective else None,
            "links": dict(self.links),
            "data": dict(self.data),
            "alert": self.alert,
        }
