#!/usr/bin/env python3
"""Validate the bundled 99-quote catalog and, optionally, source excerpts."""

from __future__ import annotations

import argparse
import json
import sys
import unicodedata
from pathlib import Path
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "Sources/CodexUsage/Resources/quotes.json"
SOURCES = {
    "analects": (4094, "pg4094.txt"),
    "laozi": (216, "pg216.txt"),
    "marcus": (2680, "pg2680.txt"),
    "epictetus": (10661, "pg10661.txt"),
    "bacon": (575, "pg575.txt"),
    "shakespeare": (2270, "pg2270.txt"),
}


def normalized(value: str) -> str:
    value = unicodedata.normalize("NFKC", value).casefold()
    return "".join(character for character in value if character.isalnum())


def source_text(key: str, source_dir: Path | None, fetch: bool) -> str | None:
    ebook_id, filename = SOURCES[key]
    if source_dir:
        path = source_dir / filename
        if not path.is_file():
            raise ValueError(f"Missing source text: {path}")
        return path.read_text(encoding="utf-8", errors="replace")
    if fetch:
        url = f"https://www.gutenberg.org/cache/epub/{ebook_id}/pg{ebook_id}.txt"
        request = Request(url, headers={"User-Agent": "CodexUsageQuoteVerifier/1.0"})
        with urlopen(request, timeout=30) as response:
            return response.read().decode("utf-8", errors="replace")
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, help="Directory with pg<ID>.txt source files")
    parser.add_argument("--fetch", action="store_true", help="Fetch all six primary texts from Project Gutenberg")
    args = parser.parse_args()

    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    quotes = catalog.get("quotes")
    if not isinstance(quotes, list) or len(quotes) != 99:
        raise ValueError("The catalog must contain exactly 99 quotes.")
    if len({quote.get("id") for quote in quotes}) != 99:
        raise ValueError("Quote IDs must be unique.")
    if len({quote.get("textEnglish") for quote in quotes}) != 99:
        raise ValueError("English quote text must be unique.")

    text_by_source: dict[str, str] = {}
    if args.source_dir or args.fetch:
        for key in SOURCES:
            text_by_source[key] = source_text(key, args.source_dir, args.fetch) or ""

    required = {
        "id", "authorChinese", "authorEnglish", "workChinese", "workEnglish",
        "locator", "locatorChinese", "textChinese", "textEnglish", "sourceURL",
        "sourceExcerpt", "sourceTextLanguage",
    }
    for quote in quotes:
        missing = sorted(field for field in required if not quote.get(field))
        if missing:
            raise ValueError(f"{quote.get('id', '<unknown>')} is missing {', '.join(missing)}")
        if not quote["sourceURL"].startswith("https://www.gutenberg.org/ebooks/"):
            raise ValueError(f"{quote['id']} has an unexpected source URL")
        group = quote["id"].split("-", 1)[0]
        if group not in SOURCES:
            raise ValueError(f"{quote['id']} has no source mapping")
        if quote["sourceTextLanguage"] not in {"zh", "en"}:
            raise ValueError(f"{quote['id']} has an unsupported source language")
        expected_translation = "App translation" if group == "analects" else "本应用译"
        translated_field = "translationEnglish" if group == "analects" else "translationChinese"
        if quote.get(translated_field) != expected_translation:
            raise ValueError(f"{quote['id']} must mark its app-authored translation")
        if quote["sourceTextLanguage"] == "en" and quote["textEnglish"] != quote["sourceExcerpt"]:
            raise ValueError(f"{quote['id']} English display must match its sourced excerpt")
        if quote["sourceTextLanguage"] == "zh" and quote.get("translationEnglish") != expected_translation:
            raise ValueError(f"{quote['id']} English text must be marked as an app translation")
        if text_by_source and normalized(quote["sourceExcerpt"]) not in normalized(text_by_source[group]):
            raise ValueError(f"{quote['id']} source excerpt does not match the cited edition")

    source_note = " and verified source excerpts" if text_by_source else ""
    print(f"99 quotes, unique IDs/texts, attribution and translation markers{source_note}: passed")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print(f"Quote verification failed: {error}", file=sys.stderr)
        sys.exit(1)
