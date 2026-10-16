# Phase 0 parity probe: Python reference vs the existing CoreML conversion.
# Both are fed the same resampled 16 kHz mono audio. The CoreML asset has a
# FIXED [1, 32000] float32 input (2.0 s), so the audio is padded/truncated to
# exactly 32000 samples for it, while the Python reference consumes the full
# (unbounded) signal.
import sys
import warnings
from pathlib import Path

import numpy as np
import torch
import torchaudio

sys.path.insert(0, str(Path(__file__).parent.parent / "myanmar_asr"))

AUDIO = Path(__file__).parent.parent / "myanmar_asr/example.mp3"

CMVN = Path(__file__).parent.parent / "myanmar_asr/cmvn.json"
VOCAB = Path(__file__).parent.parent / "myanmar_asr/vocab.json"


def load_audio(path, target_sr=16000):
    import soundfile as sf

    data, sr = sf.read(str(path), dtype="float32", always_2d=True)
    wav = torch.from_numpy(data).t()  # (channels, samples)
    if wav.shape[0] > 1:
        wav = wav.mean(dim=0, keepdim=True)
    if sr != target_sr:
        wav = torchaudio.functional.resample(wav, sr, target_sr)
    return wav.squeeze(0).numpy()


def greedy_decode(logits, vocab_size, vocab):
    ids = np.argmax(logits, axis=-1).tolist()
    out, prev = [], -1
    for i in ids:
        if i != prev and i != 0:
            out.append(i)
        prev = i
    tokens = [vocab[i] for i in out if 0 <= i < vocab_size and vocab[i]]
    return " ".join(tokens)


def main():
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        audio = load_audio(AUDIO)
    print(f"audio: {audio.shape[0]} samples = {audio.shape[0]/16000:.2f}s")

    # ---------- Python reference (full-length, fp32) ----------
    from model import ConformerASR, BLANK_ID, load_model  # noqa: E402

    with open(VOCAB, encoding="utf-8") as f:
        t2i = dict(sorted((k, v) for k, v in __import__("json").load(f).items()))
    id2tok = {v: k for k, v in t2i.items()}
    V = len(t2i)

    n = torch.from_numpy(audio).unsqueeze(0)
    mel = torchaudio.transforms.MelSpectrogram(
        sample_rate=16000, n_fft=400, win_length=400, hop_length=160, n_mels=80
    ).eval()
    import json

    cmvn = json.loads(CMVN.read_text())
    mean = torch.tensor(cmvn["mean"]).view(1, -1, 1)
    std = torch.tensor(cmvn["std"]).view(1, -1, 1)
    feats = torch.log(mel(n).clamp(min=1e-5))
    feats = (feats - mean) / (std + 1e-9)
    feats = feats.transpose(1, 2)

    model = load_model(
        str(Path(__file__).parent.parent / "myanmar_asr/model.safetensors"),
        vocab_size=V, device="cpu")
    with torch.inference_mode():
        logits, enc_lens = model(feats)
    T = feats.shape[1]
    enc = int(enc_lens[0])
    py_text = greedy_decode(logits[0, :enc].float().numpy(), V, id2tok)
    print(f"python : T={T} enc_len={enc} logits{tuple(logits.shape)}")
    print(f"python text: {py_text}")
    np.save("/tmp/py_logits_full.npy", logits[0].float().numpy())

    # ---------- Same reference but with audio zero-padded to 32000 ----------
    padded = np.zeros(32000, dtype=np.float32)
    take = min(32000, audio.shape[0])
    padded[:take] = audio[:take]
    npad = torch.from_numpy(padded).unsqueeze(0)
    feats_pad = torch.log(mel(npad).clamp(min=1e-5))
    feats_pad = (feats_pad - mean) / (std + 1e-9)
    feats_pad = feats_pad.transpose(1, 2)
    with torch.inference_mode():
        logits_pad, enc_lens_pad = model(feats_pad)
    Tpad = feats_pad.shape[1]
    print(f"padded : T={Tpad} enc_len={int(enc_lens_pad[0])}")
    np.save("/tmp/py_logits_padded.npy", logits_pad[0, :51].float().numpy())

    # ---------- Existing CoreML conversion ----------
    import coremltools as ct

    model_path = Path(__file__).parent.parent / "Models/BurmeseASR.mlpackage"
    coreml = ct.models.MLModel(str(model_path))
    inp = {"audio": torch.from_numpy(padded).unsqueeze(0).numpy()}
    out = coreml.predict(inp)
    key = list(out.keys())[0]
    arr = out[key]
    print(f"coreml : output {key} shape {arr.shape} dtype {arr.dtype}")
    coreml_text = greedy_decode(arr[0], V, id2tok)
    print(f"coreml text: {coreml_text}")

    # ---------- Compare ----------
    if arr.ndim == 3 and arr.shape[-1] == V:
        n_frames = min(arr.shape[1], logits_pad.shape[1])
        a = arr[0, :n_frames]
        b = logits_pad[0, :n_frames].float().numpy()
        print(f"logits |max abs diff| coreml vs torch(pad): {np.abs(a - b).max():.6f}")
    match = "EXACT MATCH" if coreml_text == py_text else "MISMATCH"
    print(f"parity(coreml vs python full): {match}")


if __name__ == "__main__":
    main()
