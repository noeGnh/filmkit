import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'cube_lut.dart';

/// Previews a [CubeLut] on [child] (an image, a video player…), with the same result as the
/// export.
///
/// Needs Impeller (the default renderer on Android and iOS). Without it, or until the shader
/// and the LUT texture are loaded, [child] is shown unfiltered.
class LutFilter extends StatefulWidget {
  const LutFilter({super.key, required this.lut, this.intensity = 1, required this.child});

  /// The table to apply; `null` shows [child] as is. Keep the same instance across builds:
  /// a new one uploads a new texture.
  final CubeLut? lut;

  /// 0 (no effect) to 1 (full table), as `EditSpec.lutIntensity`.
  final double intensity;

  final Widget child;

  @override
  State<LutFilter> createState() => _LutFilterState();
}

class _LutFilterState extends State<LutFilter> {
  static Future<ui.FragmentProgram>? _program;

  ui.FragmentShader? _shader;
  ui.Image? _texture;

  /// The LUT whose texture is loading or loaded.
  CubeLut? _textureLut;

  @override
  void initState() {
    super.initState();
    if (ui.ImageFilter.isShaderFilterSupported) {
      (_program ??= ui.FragmentProgram.fromAsset('packages/filmkit/shaders/lut.frag')).then((program) {
        if (mounted) setState(() => _shader = program.fragmentShader());
      });
    }
    _loadTexture();
  }

  @override
  void didUpdateWidget(LutFilter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.lut != _textureLut) _loadTexture();
  }

  Future<void> _loadTexture() async {
    final lut = widget.lut;
    _textureLut = lut;
    if (lut == null || !ui.ImageFilter.isShaderFilterSupported) return _setTexture(null);
    final texture = await lut.toTexture();
    if (!mounted || lut != _textureLut) {
      texture.dispose();
      return;
    }
    _setTexture(texture);
  }

  void _setTexture(ui.Image? texture) {
    final old = _texture;
    if (old == texture) return;
    setState(() => _texture = texture);
    // The previous frame may still use the old texture.
    if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  @override
  void dispose() {
    _texture?.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shader = _shader;
    final texture = _texture;
    final lut = widget.lut;
    if (shader == null || texture == null || lut == null || lut != _textureLut || widget.intensity <= 0) return widget.child;
    // Uniforms 0-1 (size) and sampler 0 (input) are set by the engine.
    shader
      ..setFloat(2, lut.size.toDouble())
      ..setFloat(3, widget.intensity.clamp(0, 1).toDouble())
      ..setImageSampler(1, texture);
    return ImageFiltered(imageFilter: ui.ImageFilter.shader(shader), child: widget.child);
  }
}
