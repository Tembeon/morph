# Branch validation, 2026-10-09

Flutter beta 3.49.0-0.2.pre, isolated temporary checkout. Splitting the source
requires build/import checks; it does not establish a new native speedup.

The working baseline d2f6627 passed analyze, dartdoc (zero warnings/errors),
1404 package tests, 21 example tests, macOS release, clean AUTODEMO, Wasm
and Android release compilation. Its renderer matches 1325722 byte-for-byte.

The complete integration rendering snapshot d69943c passed analyze/doc,
1423 package and 21 example tests, macOS/AUTODEMO, Wasm. Later commits
contain documentation and byte-exact archive preservation only.

Topic branch verification is in progress and will be recorded here before
the handoff is completed. Native admission states remain those in the reports.

Both evidence and integration branches reproduce all 1522 SHA-256 entries
across the four pre-existing new evidence manifests, with zero mismatches.
Archived logs are included explicitly despite the generic *.log ignore rule;
.gitattributes preserves evidence bytes. APKs and generated builds are excluded.
