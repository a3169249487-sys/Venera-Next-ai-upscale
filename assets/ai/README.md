# AI models

These ONNX models are used by the experimental manual **AI Upscale** action.

| File | Source | Notes |
|---|---|---|
| `anime4k_2x.onnx` | [kato-megumi/anime4kOnnx](https://github.com/kato-megumi/anime4kOnnx) | Anime4K model converted to float32 for the Dart ONNX Runtime binding. Original algorithm: [bloc97/Anime4K](https://github.com/bloc97/Anime4K) (MIT). |
| `anime4k_4x.onnx` | same | 4x variant, float32. |
| `waifu2x_2x.onnx` | [tcyrus/waifu2x-onnx](https://github.com/tcyrus/waifu2x-onnx) | Converted from waifu2x-caffe. Fixed 156×156 input, 284×284 output; the app crops the central 256×256. |

The upstream model repositories do not declare a license file. Anime4K itself is MIT; waifu2x-caffe model licensing should be verified before redistributing these weights. For an upstream PR, consider removing the bundled Waifu2x weights and letting the user pick a local ONNX file instead.
