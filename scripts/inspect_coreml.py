# Phase 0 analysis tool: dump the CoreML model's I/O spec, shapes, dtypes, and
# weight precision so docs/model-spec.md can be written from facts, not guesses.
# Usage: .venv/bin/python scripts/inspect_coreml.py [path-to-mlpackage]
from pathlib import Path
import sys

import coremltools as ct


def describe_type(feature):
    """Human-readable summary of one model input/output feature."""
    ft = feature.type
    kind = ft.WhichOneof("Type")
    out = f"  '{feature.name}': kind={kind}"
    if kind == "multiArrayType":
        a = ft.multiArrayType
        shape = [w if isinstance(w, int) else f"flex({w.size},{w.defaultValue})"
                 for w in (a.shape or [])]
        out += f" shape={shape} dtype={a.dataType|0}"
    elif kind == "tensorType":
        t = ft.tensorType
        shape = [w if isinstance(w, int) else f"flex({w.size},{w.defaultValue})"
                 for w in (t.shape or [])]
        out += f" shape={shape} dtype={t.dataType|0}"
    return out


def main():
    path = Path(sys.argv[1] if len(sys.argv) > 1 else "Models/BurmeseASR.mlpackage")
    model = ct.models.MLModel(str(path), skip_model_load=True)
    spec = model.get_spec()

    print(f"file: {path}")
    print(f"proto version: {spec.specificationVersion}")

    for f in spec.description.input:
        print("IN ", describe_type(f))
    for f in spec.description.output:
        print("OUT", describe_type(f))

    # Inputs may also live on the ml_program function if sourceConversion
    d = model.ml_program if getattr(model, "ml_program", None) is not None else None
    if d is not None:
        for fname, fn in d.functions.items():
            print(f"function '{fname}':")
            for name, ty in fn.input_types.items():
                print("  in ", name, ty)
            for name, ty in fn.output_types.items():
                print("  out", name, ty)

    # Weight precision: sum bytes of external weight data vs parameter count.
    weights_path = path / "Data/com.apple.CoreML/weights/weight.bin"
    if weights_path.exists():
        print(f"weight file bytes: {weights_path.stat().st_size:,}")

    md = model.user_defined_metadata
    print("metadata:", dict(md) if md else {})


if __name__ == "__main__":
    main()
