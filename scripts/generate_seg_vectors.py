#!/usr/bin/env python3
"""Generate the word-segmentation reference vectors (Phase 4, owner-approved).

This is the *reference contract* for the Swift port in PyawwCore. It runs the
upstream `mmdt-tokenizer` (0.1.3, MIT, Myanmar Data Tech) pipeline with two
documented adaptations, then writes one `input<TAB>expected` row per test
text to `Tests/Fixtures/segmentation/vectors.tsv`.

Reference behaviour:
  1. De-space — remove runs of whitespace whose neighbours on both sides are
     Myanmar word characters (letters/marks; NOT digits, NOT punctuation).
     This undoes the model's syllable-level spacing so lexicon matching can
     work across the whole word.
  2. mmdt pipeline (syllable split -> lexicon longest match -> grammar
     merges -> cleanup), with the collapse step patched so that ALL
     non-space punctuation tokens are kept (upstream silently drops
     "," "?" "!" "၊" from its output tokens).
  3. Join tokens with single spaces; no space before ။ ၊ , ? ! ;
     collapse whitespace runs; strip.

Requires:  python -m venv <tmp>; <tmp>/bin/pip install mmdt-tokenizer==0.1.3
Usage:     <tmp>/bin/python scripts/generate_seg_vectors.py
"""
import re
import sys
from pathlib import Path

import mmdt_tokenizer.tokenizer.word_tokenizer as wt
from mmdt_tokenizer import MyanmarTokenizer
from mmdt_tokenizer.rule_segmenter.config import (
    FUN_TAG,
    SPECIAL_ADJ,
    SPECIAL_POSTP_SFP,
)
from mmdt_tokenizer.rule_segmenter.types import Chunk

REPO = Path(__file__).resolve().parent.parent
OUT = REPO / "Tests/Fixtures/segmentation/vectors.tsv"

# Myanmar word characters for the de-space step: letters and marks only
# (U+1040-1049 digits and punctuation are excluded on purpose).
DESPACE_CLASS = "\\u1000-\\u103F\\u1050-\\u1097\\uA9E0-\\uA9EF\\uAA60-\\uAA7A"
DESPACE_RE = re.compile(rf"(?<=[{DESPACE_CLASS}])\s+(?=[{DESPACE_CLASS}])")
ATTACH_RE = re.compile(r"\s+([၊။,?!])")
SPACES_RE = re.compile(r"\s+")


def despace_myanmar(text: str) -> str:
    return DESPACE_RE.sub("", text)


def _patched_collapse(chunks):
    """Upstream collapse_to_phrase_chunks with the kept-punctuation fix."""
    out, tokens = [], []
    for sent in chunks:
        phrase_chunks, surface = [], []
        buf_text, buf_start, buf_end = [], None, None

        def flush_buf():
            nonlocal buf_text, buf_start, buf_end
            if not buf_text or buf_start is None or buf_end is None:
                return
            phrase_text = "".join(buf_text)
            phrase_chunks.append(Chunk(span=(buf_start, buf_end), text=phrase_text, tag="RAW"))
            surface.append(phrase_text)
            buf_text, buf_start, buf_end = [], None, None

        for ch in sent:
            tag, txt, (s0, s1) = ch.tag, ch.text, ch.span
            if tag == "PUNCT":
                if txt in (" ", ""):
                    flush_buf()
                else:  # keep every punctuation token (upstream drops most)
                    flush_buf()
                    phrase_chunks.append(Chunk(span=ch.span, text=txt, tag="PUNCT"))
                    surface.append(txt)
                continue
            if tag in FUN_TAG or txt in SPECIAL_POSTP_SFP:
                if txt in SPECIAL_ADJ:
                    if buf_start is None:
                        buf_start = s0
                    buf_end = s1
                    buf_text.append(txt)
                    flush_buf()
                else:
                    flush_buf()
                    phrase_chunks.append(ch)
                    surface.append(txt)
                continue
            if buf_start is None:
                buf_start = s0
            buf_end = s1
            buf_text.append(txt)

        flush_buf()
        phrase_chunks = [pc for pc in phrase_chunks if pc.text not in (" ", "")]
        out.append(phrase_chunks)
        tokens.append([t for t in surface if t not in (" ", "")])
    return out, tokens


wt.collapse_to_phrase_chunks = _patched_collapse
_TOKENIZER = MyanmarTokenizer()


def segment(text: str) -> str:
    if not text.strip():
        return ""
    despaced = despace_myanmar(text)
    lists = _TOKENIZER.word_tokenize(despaced, return_list=True)
    tokens = lists[0] if lists else []
    out = " ".join(tokens)
    out = ATTACH_RE.sub(r"\1", out)
    out = SPACES_RE.sub(" ", out).strip()
    return out


def main() -> None:
    fixtures = REPO / "Tests/Fixtures"
    stems = sorted(p.stem for p in (fixtures / "expected").glob("g*.txt"))
    inputs = []
    for stem in stems:
        inputs.append((fixtures / "transcripts" / f"{stem}.txt").read_text(encoding="utf-8").strip())
    for stem in stems:
        inputs.append((fixtures / "expected" / f"{stem}.txt").read_text(encoding="utf-8").strip())
    inputs += [
        "",
        "   ",
        "၁၂၃",
        "abc",
        "abc def",
        "ကျွန်တော် ကို ခေါ်ပါ။ အဆင်ပြေလား",
        "ဒီနေ့ ရက်စွဲ ၂၀၂၆ ခုနှစ် အောက်တိုဘာ ၁၇ ရက်၊ အချိန် ၁၀:၃၀ နာရီ။",
        "Python 3.11 နှင့် macOS မှာ စမ်းသပ်တယ်။ အီးမေးလ် test@example.com",
        "ကျွန်တော်၊ ပြီးတော့ သူတို့ဟာ စားသောက်ဆိုင်မှာ စားကြတယ်။",
        "ကျွန်တော်။ ကျွန်တော်",
        "မြန်မာ၊ ပြီးတော့",
        "ကျွန်တော်  ပြော",
        "APS ဖော်မတ် ပုံစံ",
        "၁၂၃၄၅၆ ကျပ်",
        "10:30 နာရီ",
        "2026-10-17 ရက်",
        "https://example.com မှာ",
        "ကျွန်တော်? ဟုတ်လား!",
        "ဟာ ဟာ ဟာ",
        "ကို ကို",
    ]
    # de-duplicate, keep order
    seen, unique = set(), []
    for text in inputs:
        if text not in seen:
            seen.add(text)
            unique.append(text)

    rows = []
    idempotence_misses = 0
    for text in unique:
        expected = segment(text)
        if segment(expected) != expected:
            idempotence_misses += 1
        assert "\t" not in text and "\n" not in text, repr(text)
        rows.append((text, expected))

    OUT.parent.mkdir(parents=True, exist_ok=True)
    header = ("# Word-segmentation reference vectors (input<TAB>expected).\n"
              "# Generated by scripts/generate_seg_vectors.py with\n"
              "# mmdt-tokenizer 0.1.3 (MIT) + patched collapse (keeps punctuation).\n"
              "# Do not edit by hand.\n")
    body = "".join(f"{t}\t{e}\n" for t, e in rows)
    OUT.write_text(header + body, encoding="utf-8")
    print(f"rows: {len(rows)}  -> {OUT.relative_to(REPO)}")
    print(f"idempotence misses: {idempotence_misses}")
    print("--- sample rows:")
    for text, expected in rows[-12:]:
        print(f"  in : {text!r}\n  out: {expected!r}")


if __name__ == "__main__":
    sys.exit(main())
