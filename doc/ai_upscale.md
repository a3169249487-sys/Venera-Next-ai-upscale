# AI 放大（实验）

阅读器顶栏新增 **AI Upscale** 按钮：对当前页做一次手动超分，结果在独立预览页中显示，可对比原图、保存或分享。它不接入正常翻页链路，也不会修改原图缓存。

这是实验功能，默认不参与阅读流程；处理大图时可能占用较多内存和时间。

## 入口

1. 打开任意章节。
2. 顶栏点 ✨（AI Upscale）。
3. 选择模式：
   - **Anime4K 2x**：轻量、快，适合线条清晰的漫画。
   - **Anime4K 4x**：更慢、输出更大。
   - **Waifu2x 2x**：神经网络降噪+2x，适合彩页/照片，速度最慢。

## 实现

- `lib/foundation/ai_upscale.dart`
  - 解码原图 → RGBA
  - 在 worker isolate 中通过 `onnxruntime` 推理
  - 128px 分块 + 8px 重叠，块内取核心区域拼接
  - 输出 PNG（`image`）
- `lib/features/reader/ai_upscale_page.dart`
  - 预览、原图/结果对比、保存、分享
- `lib/features/reader/scaffold.dart`
  - 顶栏新增 AI Upscale 入口，读取当前页字节并打开预览

不做的事：

- 不自动增强整章
- 不接入预加载/缓存
- 不默认开启
- 不处理超过 1600 万输出像素的图片（会提示改用 2x 或裁剪）

## 模型

| 文件 | 来源 | 说明 |
|---|---|---|
| `assets/ai/anime4k_2x.onnx` | [kato-megumi/anime4kOnnx](https://github.com/kato-megumi/anime4kOnnx) | 由 Anime4K 模型转换，原项目 [bloc97/Anime4K](https://github.com/bloc97/Anime4K)（MIT） |
| `assets/ai/anime4k_4x.onnx` | 同上 | 4x 模型 |
| `assets/ai/waifu2x_2x.onnx` | [tcyrus/waifu2x-onnx](https://github.com/tcyrus/waifu2x-onnx) | 由 waifu2x-caffe 模型转换，固定 156 输入 / 284 输出，中心裁剪 256 |

> 模型仓库本身没有显式 LICENSE 文件；上游算法／模型项目分别为 Anime4K（MIT）和 waifu2x-caffe（MIT）。分发前仍建议确认模型权重的授权，或改为让用户选择本地 ONNX 文件。

Anime4K 原始模型是 `float16`，`onnxruntime` 的 Dart 封装只支持 `float32`，所以用 `tool/convert_anime4k_to_f32.py` 做了类型转换。Waifu2x 模型保持原样。

## 性能

- 每块 128×128；2x 输出 256×256，4x 输出 512×512。
- 1024×1536 的页面，2x 大约需要数秒（取决于设备 CPU）。
- 4x 输出上限约 1600 万像素；再大请用 2x。
- ONNX Runtime 默认使用 CPU；移动端没有 GPU delegate。

## 开发

```bash
flutter pub get
flutter run
```

模型转换（需要 Python `onnx`）：

```bash
python tool/convert_anime4k_to_f32.py \
  assets/ai/anime4k_2x.onnx assets/ai/anime4k_2x_f32.onnx
```

如果你不想内置 Waifu2x 模型，删除 `assets/ai/waifu2x_2x.onnx` 并把 `AiUpscaleMode.waifu2x2x` 从枚举中移除，或改为文件选择。

## 已验证

- lutter analyze：新增文件和修改文件无 issue。
- lutter test test/features/reader/bottom_actions_test.dart：通过。
- lutter test test/foundation/ai_upscale_runtime_test.dart：默认跳过；设置 AI_UPSCALE_RUNTIME_TEST=1 并对测试进程提供 ONNX Runtime 原生库后，三种模型都会在 16×16 输入上输出正确倍率。Windows 下可把 onnxruntime-1.4.1/windows 加入 PATH。
