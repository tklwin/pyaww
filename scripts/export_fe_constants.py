# Export the Swift feature-extractor constants (SPEC I-8) generated from the
# Python reference front-end configuration (myanmar_asr/transcribe.py +
# preprocessor_config.json: torchaudio defaults, mel_scale='htk', norm=None,
# periodic Hann, center=True, power=2.0).
#
# Writes to Models/:
#   mel_filters.json   (80, 201)  mel filterbank matrix, rows = mel bands,
#                                 columns = FFT bins 0..200 (fp32 values)
#   hann_window.json   (400,)     periodic Hann window (torch.hann_window(400))
#
# Models/cmvn.json and Models/vocab.json already exist and are verified against
# the reference values by this script (it does not rewrite them).
#
# Note (2026-10-16): the mel_filters.json present in Models/ was Slaney-
# normalized (torchaudio norm='slaney') which does NOT match the reference
# pipeline; this script preserves it as Models/mel_filters.slaney.json for
# provenance and writes the reference-correct matrix to mel_filters.json.
# Flagged to the owner in the Phase 0 report.
#
# Usage: .venv/bin/python scripts/export_fe_constants.py
import json
import shutil
import warnings
from pathlib import Path

import numpy as np
import torch
import torchaudio

REPO = Path(__file__).resolve().parent.parent
MODELS = REPO / "Models"


def main():
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        # Reference config == transcribe.py MelSpectrogram args (defaults otherwise)
        mel = torchaudio.transforms.MelSpectrogram(
            sample_rate=16000, n_fft=400, win_length=400,
            hop_length=160, n_mels=80)
        fb = mel.mel_scale.fb.numpy().T          # (80, 201) = fb.t()
        window = torch.hann_window(400).numpy()  # periodic (torch default)

    out_fb = MODELS / "mel_filters.json"
    legacy = MODELS / "mel_filters.slaney.json"
    if out_fb.exists() and not legacy.exists():
        prev = np.array(json.loads(out_fb.read_text(encoding="utf-8")))
        if prev.shape != fb.shape or not np.allclose(prev, fb, atol=1e-9):
            shutil.copy2(out_fb, legacy)
            print(f"preserved previous mel_filters.json -> {legacy.name}")
    out_fb.write_text(json.dumps(fb.tolist()), encoding="utf-8")
    (MODELS / "hann_window.json").write_text(
        json.dumps(window.tolist()), encoding="utf-8")
    print(f"wrote {out_fb.name} {fb.shape} and hann_window.json {window.shape}")

    # Verify the owner-provided constants against the reference values.
    ref_cmvn = json.loads((REPO / "myanmar_asr/cmvn.json").read_text(
        encoding="utf-8"))
    own_cmvn = json.loads((MODELS / "cmvn.json").read_text(encoding="utf-8"))
    ok_cmvn = (np.allclose(np.array(ref_cmvn["mean"]),
                           np.array(own_cmvn["mean"]), atol=1e-6)
               and np.allclose(np.array(ref_cmvn["std"]),
                               np.array(own_cmvn["std"]), atol=1e-6))
    ref_vocab = json.loads((REPO / "myanmar_asr/vocab.json").read_text(
        encoding="utf-8"))
    own_vocab = json.loads((MODELS / "vocab.json").read_text(encoding="utf-8"))
    ok_vocab = ref_vocab == own_vocab
    print(f"cmvn.json matches reference: {ok_cmvn}; "
          f"vocab.json matches reference: {ok_vocab}")
    assert ok_cmvn and ok_vocab, "owner constants diverge from reference"


if __name__ == "__main__":
    main()
