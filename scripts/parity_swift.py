# Gate 1 comparator: Swift CLI outputs vs the Python reference outputs.
#
# Input:  TSV from pyaww-cli ("<name>\t<text>" per line)
#         Tests/Fixtures/manifest.tsv          (the 100 golden stems)
#         Tests/Fixtures/expected/<stem>.txt   (Python reference outputs)
#         Tests/Fixtures/transcripts/<stem>.txt (owner gold transcripts)
# Writes: Tests/Fixtures/parity_swift_report.tsv
#         Tests/Fixtures/cer_swift_report.tsv
#
# Policy (docs/decisions.md): every golden stem must match the Python
# reference exactly, except g2063 whose one-token difference is the
# owner-approved w16 tolerance. example.mp3 is reported but not gated: it
# is decoded by a different MP3 decoder than the Python reference.
#
# Usage: python3 scripts/parity_swift.py <swift_outputs.tsv>
import statistics
import sys
from pathlib import Path

from cer import levenshtein, strip_ws

REPO = Path(__file__).resolve().parent.parent
FIX = REPO / "Tests/Fixtures"
KNOWN_TOLERANCE = {"g2063"}
CER_BUDGET_PP = 0.1  # quality gate: Swift CER <= Python CER + 0.1 percentage points


def read_outputs(path: Path) -> dict[str, str]:
    outputs: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        name, _, text = line.partition("\t")
        outputs[Path(name).stem] = text.strip()
    return outputs


def golden_stems() -> list[str]:
    lines = (FIX / "manifest.tsv").read_text(encoding="utf-8").splitlines()
    return [line.split("\t")[0] for line in lines[1:] if line.strip()]


def cer_over(stems, hypotheses) -> tuple[int, int, list[tuple[str, int, int, int, float]]]:
    """Corpus + per-clip CER against the gold transcripts."""
    rows, total_edits, total_ref = [], 0, 0
    for stem in sorted(stems):
        transcript = FIX / "transcripts" / f"{stem}.txt"
        if stem not in hypotheses or not transcript.exists():
            continue
        reference = strip_ws(transcript.read_text(encoding="utf-8"))
        hypothesis = strip_ws(hypotheses[stem])
        edits = levenshtein(hypothesis, reference)
        cer = edits / max(len(reference), 1)
        rows.append((stem, len(reference), len(hypothesis), edits, cer))
        total_edits += edits
        total_ref += len(reference)
    return total_edits, total_ref, rows


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit("usage: python3 scripts/parity_swift.py <swift_outputs.tsv>")
    swift = read_outputs(Path(sys.argv[1]))
    golden = golden_stems()
    expected = {
        stem: (FIX / "expected" / f"{stem}.txt").read_text(encoding="utf-8").strip()
        for stem in golden
    }

    failures: list[str] = []
    report_rows: list[tuple[str, str, int, str]] = []
    mismatches: list[str] = []
    for stem in golden:
        if stem not in swift:
            failures.append(f"{stem}: missing from Swift outputs")
            continue
        hypothesis = swift[stem]
        reference = expected[stem]
        edits = levenshtein(strip_ws(hypothesis), strip_ws(reference))
        match = hypothesis == reference
        if not match:
            mismatches.append(stem)
            if stem not in KNOWN_TOLERANCE:
                failures.append(f"{stem}: unexpected mismatch ({edits} char edits)")
        report_rows.append((stem, "yes" if match else "no", edits, ""))

    for stem in mismatches:
        note = ("known tolerance: owner-approved one-token w16 difference"
                if stem in KNOWN_TOLERANCE else "UNEXPECTED")
        report_rows = [
            (s, m, e, note if s == stem else n) for s, m, e, n in report_rows]
    lines = ["stem\ttext_match\tchar_edits_vs_python\tnote"] + [
        f"{s}\t{m}\t{e}\t{n}" for s, m, e, n in report_rows]
    (FIX / "parity_swift_report.tsv").write_text("\n".join(lines) + "\n", encoding="utf-8")

    swift_edits, swift_ref, swift_rows = cer_over(golden, swift)
    python_edits, python_ref, _ = cer_over(golden, expected)
    cer_lines = ["stem\tref_chars\thyp_chars\tedits\tcer"] + [
        f"{s}\t{r}\t{h}\t{e}\t{c:.4f}" for s, r, h, e, c in swift_rows]
    (FIX / "cer_swift_report.tsv").write_text("\n".join(cer_lines) + "\n", encoding="utf-8")

    # --- summary ---
    print(f"golden stems: {len(golden)}")
    exact = len(golden) - len(mismatches) - sum("missing" in f for f in failures)
    print(f"exact matches vs Python reference: {exact}/{len(golden)}")
    for stem in mismatches:
        hypothesis = swift[stem]
        reference = expected[stem]
        tag = "known tolerance" if stem in KNOWN_TOLERANCE else "FAILURE"
        print(f"  mismatch {stem} ({tag}): python '{reference}'")
        print(f"  {' ' * len(stem)}                  swift  '{hypothesis}'")

    if "example" in swift and (FIX / "expected" / "example.txt").exists():
        reference = (FIX / "expected" / "example.txt").read_text(encoding="utf-8").strip()
        state = "exact match" if swift["example"] == reference else "differs (mp3 decoder, not gated)"
        print(f"bonus example.mp3 vs Python: {state}")

    if swift_ref:
        swift_corpus = swift_edits / max(swift_ref, 1)
        python_corpus = python_edits / max(python_ref, 1)
        delta_pp = (swift_corpus - python_corpus) * 100
        median = statistics.median(c for *_, c in swift_rows)
        print(f"CER vs gold transcripts (corpus): swift {swift_corpus:.4%} | "
              f"python {python_corpus:.4%} | delta {delta_pp:+.2f} pp")
        print(f"CER swift median clip: {median:.4%} | worst: "
              f"{max(swift_rows, key=lambda r: r[4])[0]} "
              f"{max(c for *_, c in swift_rows):.4%}")
        if delta_pp > CER_BUDGET_PP + 1e-9:
            failures.append(f"quality gate: Swift CER exceeds Python CER by {delta_pp:.2f} pp "
                            f"(budget {CER_BUDGET_PP} pp)")

    print(f"reports: {FIX / 'parity_swift_report.tsv'}")
    print(f"         {FIX / 'cer_swift_report.tsv'}")
    if failures:
        print("PARITY FAILED:")
        for failure in failures:
            print(f"  - {failure}")
        sys.exit(1)
    print("PARITY PASSED")


if __name__ == "__main__":
    main()
