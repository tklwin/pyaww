# Phase 0/1 tooling: run the owner's Python reference over golden WAVs and
# produce the fixtures the parity tests consume:
#   Tests/Fixtures/expected/<stem>.txt        reference output text
#   Tests/Fixtures/intermediates/<stem>/      per-stage tensors (first N files)
#   Tests/Fixtures/parity_report.tsv          (with --verify-coreml)
# Every value comes from the reference code paths in myanmar_asr — nothing
# here re-implements or invents front-end behaviour. The padded/masked inputs
# are derived from the reference features by the documented formulas
# (see scripts/reconvert_coreml.py — same helpers).
# Usage:
#   .venv/bin/python scripts/export_fixtures.py [audio files or dirs] \
#       --intermediates 4 --out Tests/Fixtures \
#       --verify-coreml Models/BurmeseASR-Encoder-30s.mlpackage
import argparse
import json
import sys
import time
import warnings
from pathlib import Path

import numpy as np
import soundfile as sf
import torch
import torchaudio

REPO = Path(__file__).parent.parent
sys.path.insert(0, str(REPO / "myanmar_asr"))
sys.path.insert(0, str(REPO / "scripts"))
from model import load_model  # noqa: E402  (owner's reference code)
import reconvert_coreml as rc  # noqa: E402  (30 s model input formulas)


def resampled_16k(path: Path) -> np.ndarray:
    data, sr = sf.read(str(path), dtype="float32", always_2d=True)
    wav = torch.from_numpy(data).t()
    if wav.shape[0] > 1:
        wav = wav.mean(dim=0, keepdim=True)
    if sr != 16000:
        wav = torchaudio.functional.resample(wav, sr, 16000)
    return wav.squeeze(0).numpy().astype(np.float32)


def reference_pipeline(pcm: np.ndarray, mel, cmvn, model, id2tok):
    """Mirror transcribe.py exactly: clamped log-mel, CMVN, CTC greedy."""
    n = torch.from_numpy(pcm).unsqueeze(0)
    feats = torch.log(mel(n).clamp(min=1e-5))
    feats = (feats - cmvn["mean"]) / (cmvn["std"] + 1e-9)
    feats = feats.transpose(1, 2)
    with torch.inference_mode():
        logits, enc_lens = model(feats)
    T = int(logits.shape[1])
    enc = int(enc_lens[0])
    best = torch.argmax(logits, dim=-1)
    ids, out, prev = best[0, :enc].tolist(), [], -1
    for i in ids:
        if i != prev and i != 0:
            out.append(i)
        prev = i
    tokens = [id2tok[i] for i in out if 0 <= i < len(id2tok) and id2tok[i]]
    return {
        "num_frames": T,
        "enc_len": enc,
        "logits": logits[0, :enc].float().numpy(),
        "token_ids": out,
        "text": " ".join(tokens),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("inputs", nargs="*", help="audio files or directories")
    ap.add_argument("--intermediates", type=int, default=4,
                    help="save per-stage tensors for the first N files")
    ap.add_argument("--out", default=str(REPO / "Tests/Fixtures"))
    ap.add_argument("--pad-to", type=int, default=480000,
                    help="pad/trim length for the fixed 30 s model input")
    ap.add_argument("--verify-coreml", default=None,
                    help="path to the converted .mlpackage to verify against "
                         "the reference (writes parity_report.tsv)")
    args = ap.parse_args()

    paths: list[Path] = []
    for raw in args.inputs or [str(REPO / "myanmar_asr/example.mp3")]:
        p = Path(raw)
        paths += sorted([q for q in p.iterdir()
                         if q.suffix.lower() in {".wav", ".mp3", ".flac"}]) if p.is_dir() else [p]

    out = Path(args.out)
    exp = out / "expected"; exp.mkdir(parents=True, exist_ok=True)
    inter = out / "intermediates"; inter.mkdir(parents=True, exist_ok=True)

    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        import model as ref  # owner's module

        t2i = json.loads((REPO / "myanmar_asr/vocab.json").read_text(encoding="utf-8"))
        id2tok = {v: k for k, v in t2i.items()}
        V = len(id2tok)
        cmvn_raw = json.loads((REPO / "myanmar_asr/cmvn.json").read_text())
        cmvn = {"mean": torch.tensor(cmvn_raw["mean"]).view(1, -1, 1),
                "std": torch.tensor(cmvn_raw["std"]).view(1, -1, 1)}
        mel = torchaudio.transforms.MelSpectrogram(
            sample_rate=16000, n_fft=400, win_length=400,
            hop_length=160, n_mels=80).eval()
        model = load_model(str(REPO / "myanmar_asr/model.safetensors"),
                           vocab_size=len(t2i), device="cpu")

    coreml = None
    if args.verify_coreml:
        import coremltools as ct
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            coreml = ct.models.MLModel(args.verify_coreml)
        out_name = coreml.get_spec().description.output[0].name
        report_lines = ["stem\tsamples\tmel_frames\tR\tmax_abs_diff"
                        "\targmax_agree\ttext_match\ttime_ms"]

    def ref_features(pcm: np.ndarray) -> torch.Tensor:
        f = torch.log(mel(torch.from_numpy(pcm).unsqueeze(0)).clamp(min=1e-5))
        f = ((f - cmvn["mean"]) / (cmvn["std"] + 1e-9)).transpose(1, 2)
        return f                                  # (1, T, 80)

    def greedy_text(logits: torch.Tensor, rows: int) -> str:
        best = logits[0, :rows].argmax(-1)
        ids, out, prev = best.tolist(), [], -1
        for i in ids:
            if i != prev and i != 0:
                out.append(i)
            prev = i
        return " ".join(id2tok[i] for i in out
                        if 0 <= i < V and id2tok[i])

    n_verified, n_text_ok = 0, 0
    made, inter_saved = [], 0
    for path in paths:
        pcm = resampled_16k(path)
        if pcm.shape[0] < 8000:  # reference returns "" below 0.5 s
            result = {"text": "", "num_frames": 0, "enc_len": 0,
                      "token_ids": []}
        else:
            result = reference_pipeline(pcm, mel, cmvn, model, id2tok)
        (exp / f"{path.stem}.txt").write_text(result["text"] + "\n",
                                              encoding="utf-8")
        made.append(path.name)

        feats = None
        if result.get("num_frames"):
            feats = ref_features(pcm)             # (1, T, 80)

        if coreml is not None and feats is not None:
            padded, fb, cb, R = rc.make_inputs(feats)
            t0 = time.perf_counter()
            arr = np.asarray(coreml.predict(
                {"mel": padded.numpy(),
                 "frame_bias": fb.numpy(),
                 "conv1_bias": cb.numpy()})[out_name])
            dt_ms = (time.perf_counter() - t0) * 1e3
            valid = arr[0, :R].astype(np.float64)
            ref = result["logits"].astype(np.float64)
            maxd = float(np.abs(valid - ref).max())
            agree = float((valid.argmax(-1) == ref.argmax(-1)).mean())
            text_cm = greedy_text(torch.from_numpy(arr), R)
            text_ok = text_cm == result["text"]
            n_verified += 1
            n_text_ok += text_ok
            report_lines.append(
                f"{path.stem}\t{pcm.shape[0]}\t{feats.shape[1]}\t{R}"
                f"\t{maxd:.4f}\t{agree:.4f}\t{'yes' if text_ok else 'NO'}"
                f"\t{dt_ms:.1f}")

        if inter_saved < args.intermediates:
            d = inter / path.stem
            d.mkdir(parents=True, exist_ok=True)
            np.save(d / "samples_full.npy", pcm)
            if feats is not None:
                padded, fb, cb, R = rc.make_inputs(feats)
                np.save(d / "mel_cmvn_full.npy", feats.squeeze(0).numpy())
                np.save(d / "mel_cmvn_padded.npy", padded.squeeze(0).numpy())
                np.save(d / "frame_bias.npy", fb.squeeze(0).numpy())
                np.save(d / "conv1_bias.npy", cb.squeeze(0).numpy())
                np.save(d / "logits_full.npy", result["logits"])
            meta = {
                "source": str(path.resolve().relative_to(REPO.resolve())),
                "samples_full": int(pcm.shape[0]),
                "num_frames": result["num_frames"],
                "enc_len": result["enc_len"],
                "token_ids": result["token_ids"],
                "text": result["text"],
            }
            (d / "meta.json").write_text(
                json.dumps(meta, ensure_ascii=False, indent=2),
                encoding="utf-8")
            inter_saved += 1

    print(f"expected outputs written: {len(made)} -> {exp}")
    print(f"intermediates written for: {inter_saved} file(s) -> {inter}")
    if coreml is not None:
        rep = out / "parity_report.tsv"
        rep.write_text("\n".join(report_lines) + "\n", encoding="utf-8")
        print(f"coreml verification: {n_text_ok}/{n_verified} text matches "
              f"(report: {rep})")


if __name__ == "__main__":
    main()
