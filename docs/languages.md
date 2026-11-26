# Source language evidence

The core algorithms, data models, parsers, planners and query index are written
in MoonBit and checked on Wasm GC and JavaScript. JavaScript FFI is confined to
the process/filesystem adapters in the production CLI and verification command.
Python handles real files, subprocesses, pipes and host fault injection.

The 0.8.21 source snapshot below uses canonical Git blob bytes, not build outputs
or working-tree line endings. Comments are included. Generated `.mbti`, JSON
fixtures and documentation are excluded from source rows.

| Source category | Files | Bytes | Nonblank lines |
| --- | ---: | ---: | ---: |
| Production MoonBit, including CLI adapter | 27 | 136,288 | 4,079 |
| MoonBit regression tests for the core and CLI | 19 | 145,990 | 4,550 |
| MoonBit SDK examples | 3 | 4,790 | 137 |
| Independent MoonBit verification implementation | 5 | 59,452 | 1,917 |
| Verification selftests | 1 | 1,068 | 22 |
| Python host adapter and entry points | 6 | 36,520 | 645 |

For comparison with the repository language bar, exclude examples (which GitHub
excluded from prior measurements). This leaves 342,798 MoonBit bytes, 36,520
Python bytes and the 326-byte module manifest that GitHub previously classified
as AMPL, approximately **90.29% MoonBit by that byte metric**. GitHub can classify
files differently or update its cached bar later; its public languages API is
the authority for the displayed value.

The byte metric includes embedded FFI text. In particular, the CLI contains
488 JavaScript payload lines and the verification process bridge contains 25.
The verification inputs also carry a small JavaScript fault-injection preload.
Do not interpret the language bar as a claim that every source byte is MoonBit,
or count tests/reference tools as production functionality. No Linguist overrides
are used; `.gitattributes` only sets text line endings.

The 0.8.20 commit contained 342,131 MoonBit bytes, 36,520 Python bytes and a
326-byte manifest (90.28% by the same byte metric).
The 0.8.19 public measurement was 341,348 MoonBit bytes, 36,520 Python bytes
and 326 AMPL bytes (90.26% MoonBit), confirmed before this update.
The 0.8.18 public measurement was 339,663 MoonBit bytes, 36,520 Python bytes
and 326 AMPL bytes (90.21% MoonBit), confirmed before this update.
The 0.8.17 public measurement was 338,646 MoonBit bytes, 36,520 Python bytes
and 326 AMPL bytes (90.19% MoonBit), confirmed before this update.
The 0.8.16 public measurement was 336,516 MoonBit bytes, 36,520 Python bytes
and 326 AMPL bytes (90.13% MoonBit), confirmed before this update.
The 0.8.15 public measurement was 335,076 MoonBit bytes, 36,520 Python bytes
and 326 AMPL bytes (90.09% MoonBit), confirmed before this update.
The 0.8.14 source measurement was 333,564 MoonBit bytes, 35,677 Python bytes
and a 326-byte manifest (90.26% MoonBit by the same byte metric).
The 0.8.13 source measurement was 317,770 MoonBit bytes, 34,026 Python bytes
and a 326-byte manifest (90.24% MoonBit by the same byte metric).
The 0.8.12 public measurement was 314,367 MoonBit bytes, 34,026 Python bytes
and 326 AMPL bytes (90.15% MoonBit), confirmed before this update.
The 0.8.11 public measurement was 311,643 MoonBit bytes, 34,026 Python bytes
and 326 AMPL bytes (90.07% MoonBit), confirmed before this update.
The 0.8.10 public measurement was 307,732 MoonBit bytes, 33,400 Python bytes
and 326 AMPL bytes (90.12% MoonBit), confirmed before this update.
The 0.8.9 source measurement was 306,953 MoonBit bytes, 33,400 Python bytes
and a 325-byte manifest (90.10% MoonBit by the same byte metric).
The 0.8.8 public measurement was 301,702 MoonBit bytes, 32,819 Python bytes
and 325 AMPL bytes (90.10% MoonBit), confirmed before this update.
The 0.8.7 public measurement was 300,175 MoonBit bytes, 32,819 Python bytes
and 325 AMPL bytes (90.06% MoonBit), confirmed before this update.
The 0.8.6 source measurement was 292,167 MoonBit bytes, 31,770 Python bytes
and a 325-byte manifest (90.10% MoonBit by the same byte metric).
The 0.8.5 source measurement was 283,311 MoonBit bytes, 30,558 Python bytes
and a 325-byte manifest (90.17% MoonBit by the same byte metric).
The 0.8.4 source measurement was 279,756 MoonBit bytes, 30,558 Python bytes
and a 325-byte manifest (90.06% MoonBit by the same byte metric).
The 0.8.3 source measurement was 276,677 MoonBit bytes, 29,897 Python bytes
and a 325-byte manifest (90.15% MoonBit by the same byte metric).
The 0.8.2 source measurement was 274,005 MoonBit bytes, 29,897 Python bytes
and a 325-byte manifest (90.07% MoonBit by the same byte metric).
The 0.8.1 public measurement was 268,170 MoonBit bytes, 27,386 Python bytes and
325 AMPL bytes (90.63% MoonBit), confirmed before this update.
The 0.8.0 public measurement was 261,878 MoonBit bytes, 25,326 Python bytes and
325 AMPL bytes (91.08% MoonBit), confirmed before this update.
The 0.6.0 public measurement was 248,075 MoonBit bytes, 24,260 Python bytes and
325 AMPL bytes (90.98% MoonBit), confirmed on 2026-11-19 before this update.
The 0.5.0 public measurement was 223,192 MoonBit bytes, 22,408 Python bytes and
325 AMPL bytes (90.76% MoonBit), confirmed on 2026-11-18 before this update.
The 0.4.0 public measurement was 214,264 MoonBit bytes, 22,408 Python bytes and
325 AMPL bytes (90.41% MoonBit), confirmed on 2026-11-17 before this update.
The 0.3.0 public measurement was 205,918 MoonBit bytes, 22,408 Python bytes and
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
