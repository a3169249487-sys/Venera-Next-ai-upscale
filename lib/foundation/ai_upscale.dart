import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';

/// Experimental, manual AI upscaling. Not used by the normal reader path.
enum AiUpscaleMode {
  anime4k2x('Anime4K 2x', 'assets/ai/anime4k_2x.onnx', 2, 128, 0),
  anime4k4x('Anime4K 4x', 'assets/ai/anime4k_4x.onnx', 4, 128, 0),
  waifu2x2x('Waifu2x 2x', 'assets/ai/waifu2x_2x.onnx', 2, 128, 14);

  const AiUpscaleMode(
    this.label,
    this.assetPath,
    this.scale,
    this.tile,
    this.pad,
  );

  final String label;
  final String assetPath;
  final int scale;
  final int tile;

  /// Padding required by fixed-input models (Waifu2x: 128 + 14 * 2 = 156).
  final int pad;

  bool get isWaifu2x => this == AiUpscaleMode.waifu2x2x;
}

class AiUpscaleException implements Exception {
  AiUpscaleException(this.message);

  final String message;

  @override
  String toString() => message;
}

typedef _UpscaledRgba = ({Uint8List bytes, int width, int height});

class _DecodedImage {
  _DecodedImage(this.rgba, this.width, this.height);

  final Uint8List rgba;
  final int width;
  final int height;
}

/// Decodes the original bytes, runs a model in a worker isolate and re-encodes
/// the result as PNG. The reader's original image cache is never modified.
class AiUpscaleService {
  static const int _maxOutputPixels = 16000000;

  static Future<Uint8List> upscale(Uint8List source, AiUpscaleMode mode) async {
    final decoded = await _decode(source);
    final outWidth = decoded.width * mode.scale;
    final outHeight = decoded.height * mode.scale;
    if (outWidth * outHeight > _maxOutputPixels) {
      throw AiUpscaleException(
        'Output is too large (${outWidth}x$outHeight). '
        'Crop the page or use 2x instead of 4x.',
      );
    }

    final data = await rootBundle.load(mode.assetPath);
    final modelBytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );

    final rgba = decoded.rgba;
    final width = decoded.width;
    final height = decoded.height;
    final scale = mode.scale;
    final tile = mode.tile;
    final pad = mode.pad;
    final result = await Isolate.run<_UpscaledRgba>(() {
      return _upscaleInIsolate(
        modelBytes,
        rgba,
        width,
        height,
        scale,
        tile,
        pad,
      );
    });

    return _encodePng(result.bytes, result.width, result.height);
  }

  static Future<_DecodedImage> _decode(Uint8List bytes) async {
    ui.Codec? codec;
    ui.Image? image;
    try {
      codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      image = frame.image;
      final data = await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      if (data == null) {
        throw AiUpscaleException('Unable to decode the image.');
      }
      return _DecodedImage(
        Uint8List.fromList(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        ),
        image.width,
        image.height,
      );
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }

  static Uint8List _encodePng(Uint8List rgba, int width, int height) {
    final image = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: rgba.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    return Uint8List.fromList(img.encodePng(image));
  }
}

/// Runs in a worker isolate. Keep all ONNX objects local to this function.
_UpscaledRgba _upscaleInIsolate(
  Uint8List modelBytes,
  Uint8List rgba,
  int width,
  int height,
  int scale,
  int tile,
  int pad,
) {
  OrtEnv.instance.init(level: OrtLoggingLevel.error);
  final options = OrtSessionOptions();
  options.setIntraOpNumThreads(2);
  late final OrtSession session;
  try {
    session = OrtSession.fromBuffer(modelBytes, options);
  } finally {
    options.release();
  }

  final runOptions = OrtRunOptions();
  final inputName = session.inputNames.first;
  final inputTile = tile + pad * 2;
  final outWidth = width * scale;
  final outHeight = height * scale;
  final output = Uint8List(outWidth * outHeight * 4);

  const overlap = 8;
  final step = tile - overlap;
  final half = overlap ~/ 2;

  try {
    for (var oy = 0; oy < height; oy += step) {
      for (var ox = 0; ox < width; ox += step) {
        final coreStartX = ox == 0 ? 0 : ox + half;
        final coreStartY = oy == 0 ? 0 : oy + half;
        final coreEndX = math.min(ox + tile - half, width);
        final coreEndY = math.min(oy + tile - half, height);
        if (coreStartX >= coreEndX || coreStartY >= coreEndY) {
          continue;
        }

        final input = Float32List(3 * inputTile * inputTile);
        final planeSize = inputTile * inputTile;
        for (var y = 0; y < inputTile; y++) {
          final sy = (oy - pad + y).clamp(0, height - 1).toInt();
          for (var x = 0; x < inputTile; x++) {
            final sx = (ox - pad + x).clamp(0, width - 1).toInt();
            final src = (sy * width + sx) * 4;
            final dst = y * inputTile + x;
            input[dst] = rgba[src] / 255.0;
            input[dst + planeSize] = rgba[src + 1] / 255.0;
            input[dst + planeSize * 2] = rgba[src + 2] / 255.0;
          }
        }

        final tensor = OrtValueTensor.createTensorWithDataList(input, [
          1,
          3,
          inputTile,
          inputTile,
        ]);
        final values = session.run(runOptions, {inputName: tensor});
        final value = values.first?.value;
        if (value is! List) {
          tensor.release();
          throw AiUpscaleException('Model returned no tensor.');
        }
        final batch = value[0] as List;
        final red = batch[0] as List;
        final green = batch[1] as List;
        final blue = batch[2] as List;

        final outX0 = (coreStartX - ox + pad) * scale;
        final outY0 = (coreStartY - oy + pad) * scale;
        final copyWidth = (coreEndX - coreStartX) * scale;
        final copyHeight = (coreEndY - coreStartY) * scale;

        for (var y = 0; y < copyHeight; y++) {
          final redRow = red[outY0 + y] as List;
          final greenRow = green[outY0 + y] as List;
          final blueRow = blue[outY0 + y] as List;
          final dstY = coreStartY * scale + y;
          for (var x = 0; x < copyWidth; x++) {
            final dstX = coreStartX * scale + x;
            final dst = (dstY * outWidth + dstX) * 4;
            output[dst] = ((redRow[outX0 + x] as num) * 255)
                .round()
                .clamp(0, 255)
                .toInt();
            output[dst + 1] = ((greenRow[outX0 + x] as num) * 255)
                .round()
                .clamp(0, 255)
                .toInt();
            output[dst + 2] = ((blueRow[outX0 + x] as num) * 255)
                .round()
                .clamp(0, 255)
                .toInt();
            output[dst + 3] = 255;
          }
        }

        tensor.release();
        for (final item in values) {
          item?.release();
        }
      }
    }
  } finally {
    runOptions.release();
    session.release();
  }

  return (bytes: output, width: outWidth, height: outHeight);
}
