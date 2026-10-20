import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:venera_next/foundation/ai_upscale.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final enabled = Platform.environment['AI_UPSCALE_RUNTIME_TEST'] == '1';
  test(
    'all bundled models upscale a small image',
    () async {
      final image = img.Image(width: 16, height: 16);
      img.fill(image, color: img.ColorRgb8(200, 30, 40));
      final bytes = Uint8List.fromList(img.encodePng(image));

      for (final mode in AiUpscaleMode.values) {
        final result = await AiUpscaleService.upscale(bytes, mode);
        final decoded = img.decodePng(result);
        expect(decoded, isNotNull, reason: mode.label);
        expect(decoded!.width, 16 * mode.scale, reason: mode.label);
        expect(decoded.height, 16 * mode.scale, reason: mode.label);
      }
    },
    skip: enabled
        ? null
        : 'Requires ONNX Runtime native library in the test process.',
  );
}
