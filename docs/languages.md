# Source language evidence

The core algorithms, data models, parsers, planners and query index are written
in MoonBit and checked on Wasm GC and JavaScript. JavaScript FFI is confined to
the process/filesystem adapters in the production CLI and verification command.
Python handles real files, subprocesses, pipes and host fault injection.

The 0.4.0 source snapshot below uses canonical Git blob bytes, not build outputs
or working-tree line endings. Comments are included. Generated `.mbti`, JSON
fixtures and documentation are excluded from source rows.

| Source category | Files | Bytes | Nonblank lines |
| --- | ---: | ---: | ---: |
| Production MoonBit, including CLI adapter | 16 | 70,184 | 2,184 |
| Core MoonBit regression tests | 15 | 98,159 | 3,095 |
| MoonBit SDK examples | 3 | 3,419 | 104 |
| Independent MoonBit verification implementation | 4 | 44,853 | 1,454 |
| Verification selftests | 1 | 1,068 | 22 |
| Python host adapter and entry points | 5 | 22,408 | 407 |

For comparison with the repository language bar, exclude examples (which GitHub
excluded from its 0.2.0 and 0.3.0 measurements). This leaves 214,264 MoonBit bytes, 22,408
Python bytes and the 325-byte module manifest that GitHub previously classified
as AMPL: approximately **90.41% MoonBit by that byte metric**. GitHub can classify
files differently or update its cached bar later; its public languages API is
the authority for the displayed value.

The byte metric includes embedded FFI text. In particular, the CLI contains
146 JavaScript payload lines and the verification process bridge contains 25.
Do not interpret the language bar as a claim that every source byte is MoonBit,
or count tests/reference tools as production functionality. No Linguist overrides
are used; `.gitattributes` only sets text line endings.

The 0.3.0 public measurement is 205,918 MoonBit bytes, 22,408 Python bytes and
325 AMPL bytes (90.06% MoonBit), confirmed by the GitHub languages API on
2026-11-14 before this update. The 0.2.0 measurement was 125,593 MoonBit bytes,
39,065 Python bytes and 325 AMPL bytes (76.125% MoonBit). In 0.3.0, portable reference mathematics and case
definitions were migrated rather than duplicated; the old Python definitions
were removed from the repository. External migration checks matched 113 graph
reports, 113 DOT strings, 40 SSA reports and 425 batched-query answers exactly.
The reference uses production parsers/types but no production analysis function
to generate expected answers.

Reproduce the source accounting from `git ls-files` and canonical contents
(`git show HEAD:path` or `git cat-file`), grouping `.mbt` production, tests,
examples and `verification/` separately. Read the public language totals from
[GitHub languages](https://api.github.com/repos/Novanke/cairndom/languages).
The competition guide requires MoonBit as the main implementation language;
the numeric maintenance target here is not an invented official threshold.
