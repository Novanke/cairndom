# Release verification

1. Read AGENTS.md, README.md and docs/verification.md. Confirm a clean worktree,
   the intended public remote, and no concurrent builds or unpublished user edits.
2. Record `moon version --all`; use the compiler version pinned in CI or newer
   only after verifying the supported entry points. Update the module version
   and the README's exact dependency version together.
3. Run formatting, public-interface generation, Wasm GC and JavaScript checks
   and tests, the optimized JavaScript build, both SDK examples on both backends,
   the four Python host entry points: `verify_cli.py`, `verify_ssa_cli.py`,
   `verify_queries.py` and `verify_stdout.py`. The full JS release build includes
   the independent MoonBit reference command used by those entry points.
   Record unavailable filesystem capabilities instead of claiming they ran.
4. Review the actual source diff and commit meaningful complete changes. Push
   without rewriting remote history. Confirm that the public Windows and Linux
   jobs for that exact commit both finish successfully.
5. Run `moon package --list`. Compare every archive file byte-for-byte with the
   committed path. Do not include local reports, private application documents,
   credentials, temporary fixtures or build outputs.
6. Use the existing normal Mooncakes login and `moon publish`. Verify registry
   metadata, version, build status and archive checksum. A successful upload
   alone is not an installation test.
7. Create a new consumer outside this repository with an exact registry version
   dependency and no prior build/cache directory. Run real public-API assertions
   on both backends. Compare the installed original files with the archive and
   Git commit. Build the installed package's CLI and run all four host entry points
   against that installed CLI, including new-file refusal and stdout failures.
8. After those checks, create and push the matching version tag (prefer annotated).
   If normal Git transport fails, the GitHub release UI may create a tag fixed to
   the exact verified commit. Verify its public dereferenced commit and record
   its type. Align only a local tag created by this release, never an unrelated
   user tag. Include CI, checksum and consumer results in the tag/release notes
   or an external release evidence record.

Do not invent code volume, adoption, speed, tests or history to satisfy a numeric
target. Keep algorithm limits and planning-only semantics visible. The project
does not edit or submit competition applications as part of its release process.
