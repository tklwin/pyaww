# CER of the Python reference outputs against the owner's gold transcripts
# (HF dataset text), per SPEC 5.3 "Quality (tracked)".
#
# Convention (documented in docs/model-spec.md): strip ALL whitespace from both
# strings, do NOT apply any Unicode normalization, then
#   CER(clip)   = Levenshtein(hypothesis, reference) / len(reference)
#   corpus CER  = total edits / total reference characters
# Characters are compared as Unicode scalar values.
#
# Reads:  Tests/Fixtures/expected/<stem>.txt   (Python reference output)
#         Tests/Fixtures/transcripts/<stem>.txt (gold transcript)
# Writes: Tests/Fixtures/cer_report.tsv
# Usage:  .venv/bin/python scripts/cer.py
import statistics
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
FIX = REPO / "Tests/Fixtures"


def levenshtein(a: str, b: str) -> int:
    if len(a) < len(b):
        a, b = b, a
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1,
                           prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]


def strip_ws(text: str) -> str:
    return "".join(text.split())


def main():
    stems = sorted(p.stem for p in (FIX / "transcripts").glob("*.txt"))
    rows, total_edits, total_ref = [], 0, 0
    for stem in stems:
        exp = FIX / "expected" / f"{stem}.txt"
        if not exp.exists():
            print(f"skip {stem}: no expected output")
            continue
        ref = strip_ws((FIX / "transcripts" / f"{stem}.txt"
                        ).read_text(encoding="utf-8"))
        hyp = strip_ws(exp.read_text(encoding="utf-8"))
        edits = levenshtein(hyp, ref)
        cer = edits / max(len(ref), 1)
        rows.append((stem, len(ref), len(hyp), edits, cer))
        total_edits += edits
        total_ref += len(ref)
    lines = ["stem\tref_chars\thyp_chars\tedits\tcer"] + [
        f"{s}\t{r}\t{h}\t{e}\t{c:.4f}" for s, r, h, e, c in rows]
    (FIX / "cer_report.tsv").write_text("\n".join(lines) + "\n",
                                        encoding="utf-8")
    cers = [c for *_, c in rows]
    print(f"clips: {len(rows)}")
    print(f"corpus CER: {total_edits / max(total_ref, 1):.4f} "
          f"({total_edits} edits / {total_ref} ref chars)")
    print(f"mean clip CER: {statistics.mean(cers):.4f} | "
          f"median: {statistics.median(cers):.4f} | "
          f"p90: {sorted(cers)[int(0.9 * len(cers))]:.4f} | "
          f"worst: {max(cers):.4f} ({max(rows, key=lambda r: r[4])[0]})")
    print(f"report: {FIX / 'cer_report.tsv'}")


if __name__ == "__main__":
    main()
