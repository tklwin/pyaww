# Build the Pyaww golden test set (I-7) from the owner-approved dataset:
#   chuuhtetnaing/myanmar-speech-dataset-for-asr  (CC-BY-SA-4.0), test split.
#
# Writes, deterministically (fixed seed):
#   Tests/Fixtures/audio/<stem>.wav        original 16 kHz PCM_16 bytes
#   Tests/Fixtures/transcripts/<stem>.txt  ground truth from the dataset
#   Tests/Fixtures/manifest.tsv            stem, source, duration, held_out
#
# Stratification: duration buckets (<2 s, 2-10 s, 10-20 s, 20-30 s) and
# source diversity; ~100 clips. Every 5th clip (seeded) is marked held_out
# for the agent-tuning guard of spec section 9.1. Clips >30 s and any not
# at 16 kHz are skipped (the model takes a fixed 30 s input).
#
# Usage: .venv/bin/python scripts/make_golden_from_hf.py [--write] [--total 100]
import io
import random
from collections import Counter
from pathlib import Path

import pyarrow.parquet as pq
import soundfile as sf

REPO = Path(__file__).resolve().parent.parent
PARQUET = Path.home() / (
    ".cache/huggingface/hub/datasets--chuuhtetnaing--myanmar-speech-dataset-for-asr/"
    "snapshots/353de00dbc181c8380008963c433e6b8d6ba8589/data/test-00000-of-00001.parquet"
)
TARGET_BUCKETS = [12, 44, 24, 20]  # <2s, 2-10s, 10-20s, 20-30s
BUCKETS = [2.0, 10.0, 20.0, 30.0]


def scan():
    """Return rows: (row_index, source, duration_s, sample_rate, bytes_ok)."""
    pf = pq.ParquetFile(PARQUET)
    rows, problems = [], []
    for bi, batch in enumerate(pf.iter_batches(batch_size=32,
                                               columns=["audio", "source"])):
        for j in range(len(batch)):
            audio = batch["audio"][j].as_py()
            src = batch["source"][j].as_py()
            raw = audio["bytes"]
            try:
                info = sf.info(io.BytesIO(raw))
            except Exception as e:
                problems.append((-1, f"decode failed: {e}"))
                continue
            rows.append((bi * 32 + j, src, info.frames / info.samplerate,
                         info.samplerate, info.format, info.subtype))
    return rows, problems


def bucket_of(dur):
    for b, t in zip(TARGET_BUCKETS, BUCKETS):
        if dur < t:
            return b, dur
    return None, dur


def main(write=False, total=100):
    rows, problems = scan()
    print(f"scanned {len(rows)} rows, {len(problems)} problems: {problems[:3]}")
    print("sources:", Counter(r[1] for r in rows))
    formats = Counter((r[4], r[5]) for r in rows)
    print("formats:", formats)
    print("sample rates:", Counter(r[3] for r in rows))

    usable = [r for r in rows if r[3] == 16000 and bucket_of(r[2])[0] is not None]
    buckets = {0: [], 1: [], 2: [], 3: []}
    for r in usable:
        b = next(i for i, t in enumerate([2.0, 10.0, 20.0, 30.0])
                 if r[2] < t or i == 3)
        buckets[b].append(r)

    rng = random.Random(20261016)  # fixed seed: reproducible golden set
    for b in buckets:
        rng.shuffle(buckets[b])
    print("per-bucket available:", [len(buckets[i]) for i in range(4)])

    wants = list(TARGET_BUCKETS)
    scale = total / sum(wants)
    wants = [max(1, round(w * scale)) for w in wants]
    picked = {i: [] for i in range(4)}
    missing = 0
    for i, want in enumerate(wants):
        take_n = min(want, len(buckets[i]))
        missing += want - take_n
        picked[i] = buckets[i][:take_n]
    print(f"want={wants} missing={missing} total_picked={sum(len(v) for v in picked.values())}")

    # source diversity: guarantee at least one clip per source overall
    flat = [r for i in sorted(picked) for r in picked[i]]
    chosen_sources = {r[1] for r in flat}
    if len(chosen_sources) > 1:
        rare = [r for r in usable if r[1] not in chosen_sources][:4]
        for i in sorted(picked):
            for r in rare:
                if r[1] not in chosen_sources and r not in flat:
                    picked[i].append(r)
                    chosen_sources.add(r[1])
                    break

    flat = [r for i in sorted(picked) for r in picked[i]]

    n = 0
    manifest = []
    for b, rows_in_b in sorted(picked.items()):
        for r in rows_in_b:
            n += 1
            idx, src, dur, srate, fmt, subtype = r
            stem = f"g{b}{n:03d}"
            manifest.append([stem, b, src, round(dur, 3), 0, idx,
                             fmt, subtype])
    print(f"picked {len(manifest)} clips, per-source:",
          Counter(m[2] for m in manifest))

    # held-out: every 5th, deterministic
    manifest = sorted(manifest)  # by stem for stable ordering
    for i, entry in enumerate(manifest):
        if (i + 1) % 5 == 0:
            manifest[i][4] = 1  # held_out flag

    pf = pq.ParquetFile(PARQUET)
    audio_col, src_col, txt_col = [], [], []
    for batch in pf.iter_batches(batch_size=64,
                                 columns=["audio", "source", "transcription"]):
        audio_col.extend(batch["audio"].to_pylist())
        src_col.extend(batch["source"].to_pylist())
        txt_col.extend(batch["transcription"].to_pylist())

    if write:
        adir = REPO / "Tests/Fixtures/audio"
        tdir = REPO / "Tests/Fixtures/transcripts"
        adir.mkdir(parents=True, exist_ok=True)
        tdir.mkdir(parents=True, exist_ok=True)
        (REPO / "Tests/Fixtures/manifest.tsv").write_text(
            "stem\tduration_bucket\tsource\tduration_s\theld_out\trow_index\taudio_format\tpcm_subtype\n" +
            "\n".join("\t".join(map(str, m)) for m in manifest) + "\n",
            encoding="utf-8")
        for stem, b, src, dur, hold, idx, fmt, subtype in manifest:
            raw = audio_col[idx]["bytes"]
            (adir / f"{stem}.wav").write_bytes(raw)
            (tdir / f"{stem}.txt").write_text(txt_col[idx].strip() + "\n",
                                              encoding="utf-8")
        print(f"wrote {len(manifest)} WAVs + transcripts + manifest.tsv")
    else:
        print("(dry run — pass --write to write files)")


if __name__ == "__main__":
    import argparse

    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--total", type=int, default=100)
    a = ap.parse_args()
    main(write=a.write, total=a.total)
