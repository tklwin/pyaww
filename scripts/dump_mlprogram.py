# Dump the ml_program function I/O and op histogram for model-spec.md.
import coremltools as ct

m = ct.models.MLModel("Models/BurmeseASR.mlpackage", skip_model_load=True)
spec = m.get_spec()
for fname, fn in spec.mlProgram.functions.items():
    print(f"function {fname!r}")
    for key, blk in fn.block_specializations.items():
        print(f"  specialization {key!r}")
        print("  block inputs:")
        for item in blk.inputs:
            name = getattr(item, "name", item)
            ty = getattr(item, "type", None)
            print("   ", name, "::", (str(ty)[:110] if ty is not None else "?"))
        print("  function-level input (name,type):")
        for item in fn.inputs:
            try:
                print("   ", item[0], "::", str(item[1])[:110])
            except Exception:
                print("   ", repr(item)[:150])
        print("  block outputs:")
        for out in blk.outputs:
            print("   ", repr(out)[:150])
        ops = list(blk.operations)
        print(f"  num ops: {len(ops)}")
        if ops:
            from collections import Counter
            types = Counter(getattr(o, "op_type", type(o).__name__) for o in ops)
            print("  op histogram:", types.most_common(14))
            print("  first op:", repr(ops[0])[:200])
            print("  last op:", repr(ops[-1])[:200])
