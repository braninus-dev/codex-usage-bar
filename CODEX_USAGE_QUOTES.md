# Quote library

Codex Usage Bar ships 99 individually attributed entries. The IDs are stable. Each entry includes its author, work, locator, source URL, source-language excerpt, display text, and a translation credit where applicable. The app offers a **Source** action for the cited edition.

| Work | Count | Edition used |
| --- | ---: | --- |
| *The Analects* | 20 | [Project Gutenberg eBook 4094](https://www.gutenberg.org/ebooks/4094), James Legge edition with the original Chinese text |
| *Tao Teh King* | 20 | [Project Gutenberg eBook 216](https://www.gutenberg.org/ebooks/216), translated by James Legge |
| *Meditations* | 15 | [Project Gutenberg eBook 2680](https://www.gutenberg.org/ebooks/2680), translated by George Long |
| *The Encheiridion* | 15 | [Project Gutenberg eBook 10661](https://www.gutenberg.org/ebooks/10661), translated by George Long |
| Bacon’s *Essays* | 15 | [Project Gutenberg eBook 575](https://www.gutenberg.org/ebooks/575) |
| Shakespeare’s plays | 14 | [Project Gutenberg eBook 2270](https://www.gutenberg.org/ebooks/2270), First Folio text |

The Analects entries use the source’s Chinese text; their English display is labeled **App translation**. For the other works, the English excerpt is checked against the linked edition and the Chinese display is labeled **本应用译**. Work titles and locators are localized in the interface. App-authored translations are deliberately marked instead of being presented as a named translator’s wording.

## Check the catalog

The normal verification suite checks the count, unique IDs and English texts, required attribution, secure source links, and translation markers:

```sh
python3 scripts/verify_quote_library.py
```

The source audit can fetch the six Project Gutenberg plain-text editions and compare every stored excerpt against the cited source:

```sh
python3 scripts/verify_quote_library.py --fetch
```

Or pass a directory containing `pg4094.txt`, `pg216.txt`, `pg2680.txt`, `pg10661.txt`, `pg575.txt`, and `pg2270.txt` with `--source-dir PATH`.

Project Gutenberg’s editions are used as source references, not as a claim that every excerpt is public domain in every jurisdiction. Confirm local rights and attribution requirements before redistributing quote material. The utility’s source code is MIT licensed; quote text retains its own source and translation status.
