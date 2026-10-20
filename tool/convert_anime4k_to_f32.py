#!/usr/bin/env python3
"""Convert a float16 Anime4K ONNX model to float32 for onnxruntime Dart.

Usage:
  python tool/convert_anime4k_to_f32.py input.onnx output.onnx
"""
import sys

import numpy as np
import onnx
from onnx import TensorProto, numpy_helper


def main(src: str, dst: str) -> None:
    model = onnx.load(src)

    for value_info in (
        list(model.graph.input)
        + list(model.graph.output)
        + list(model.graph.value_info)
    ):
        tensor_type = value_info.type.tensor_type
        if tensor_type.elem_type == TensorProto.FLOAT16:
            tensor_type.elem_type = TensorProto.FLOAT

    for initializer in model.graph.initializer:
        if initializer.data_type == TensorProto.FLOAT16:
            array = numpy_helper.to_array(initializer).astype(np.float32)
            initializer.CopyFrom(
                numpy_helper.from_array(array, initializer.name)
            )

    for node in model.graph.node:
        if node.op_type != "Cast":
            continue
        for attribute in node.attribute:
            if attribute.name == "to" and attribute.i == TensorProto.FLOAT16:
                attribute.i = TensorProto.FLOAT

    onnx.checker.check_model(model)
    onnx.save(model, dst)
    print(f"wrote {dst}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    main(sys.argv[1], sys.argv[2])
