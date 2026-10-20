import 'package:flutter/material.dart';
import 'package:venera_next/components/file_save_task.dart';
import 'package:venera_next/foundation/ai_upscale.dart';
import 'package:venera_next/foundation/context.dart';
import 'package:venera_next/foundation/file_interaction.dart';

Future<AiUpscaleMode?> showAiUpscaleModeSheet(BuildContext context) {
  return showModalBottomSheet<AiUpscaleMode>(
    context: context,
    builder: (context) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('AI Upscale'),
              subtitle: Text(
                'Experimental. Runs once for the current page; the original '
                'image is not modified.',
              ),
            ),
            for (final mode in AiUpscaleMode.values)
              ListTile(
                title: Text(mode.label),
                subtitle: Text(
                  mode.isWaifu2x
                      ? 'Neural network, slower, better for photos'
                      : 'Shader-like CNN, faster, for anime line art',
                ),
                onTap: () => Navigator.of(context).pop(mode),
              ),
          ],
        ),
      );
    },
  );
}

class AiUpscalePage extends StatefulWidget {
  const AiUpscalePage({
    super.key,
    required this.bytes,
    required this.filename,
    required this.mode,
  });

  final Uint8List bytes;
  final String filename;
  final AiUpscaleMode mode;

  @override
  State<AiUpscalePage> createState() => _AiUpscalePageState();
}

class _AiUpscalePageState extends State<AiUpscalePage> {
  Uint8List? _result;
  Object? _error;
  bool _showOriginal = false;
  bool _running = true;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _error = null;
      _result = null;
      _showOriginal = false;
    });
    try {
      final result = await AiUpscaleService.upscale(widget.bytes, widget.mode);
      if (!mounted) return;
      setState(() {
        _result = result;
        _running = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _running = false;
      });
    }
  }

  String get _outputName {
    final dot = widget.filename.lastIndexOf('.');
    final stem = dot > 0 ? widget.filename.substring(0, dot) : widget.filename;
    return '${stem}_${widget.mode.name}.png';
  }

  Future<void> _save() async {
    final result = _result;
    if (result == null || !mounted) return;
    await saveFileForWindow(context, data: result, filename: _outputName);
  }

  void _share() {
    final result = _result;
    if (result == null || !mounted) return;
    Share.shareFile(
      data: result,
      filename: _outputName,
      mime: 'image/png',
      resolveOrigin: () => context.sharePositionOrigin,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('AI Upscale · ${widget.mode.label}'),
        actions: [
          if (_result != null)
            IconButton(
              tooltip: _showOriginal ? 'Show result' : 'Show original',
              icon: Icon(_showOriginal ? Icons.auto_awesome : Icons.compare),
              onPressed: () => setState(() => _showOriginal = !_showOriginal),
            ),
          if (_result != null)
            IconButton(
              tooltip: 'Save',
              icon: const Icon(Icons.download),
              onPressed: _save,
            ),
          if (_result != null)
            IconButton(
              tooltip: 'Share',
              icon: const Icon(Icons.share),
              onPressed: _share,
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_running) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Upscaling…'),
          ],
        ),
      );
    }

    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40),
              const SizedBox(height: 12),
              Text(error.toString(), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _run, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final result = _result!;
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 8,
      child: Center(
        child: Image.memory(
          _showOriginal ? widget.bytes : result,
          fit: BoxFit.contain,
          gaplessPlayback: true,
        ),
      ),
    );
  }
}
