# Contributing

**The most useful help now is a device report.** If you try PadTerm on any iPad, open a [device report](../../issues/new?template=device-report.yml), even if all works.

For code:

1. Read the [README](README.md) build section. You need an Apple Silicon Mac and Command Line Tools.
2. Run `scripts/run_tests.sh`, and `tests/modern/run_bench.sh` for a UI change.
3. Keep iOS 6 working: an API newer than iOS 6 must sit behind a runtime check, and `@available` does not link for armv7.
4. Do not commit keys, test captures or third-party art. `scripts/check_release.py` checks this.
