import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

class FaceMatchResult {
  const FaceMatchResult({
    required this.passed,
    required this.score,
  });

  final bool passed;
  final double score;
}

class FaceMatchService {
  const FaceMatchService();

  static const double passThreshold = 0.82;

  Future<String> createSignature(Uint8List bytes) async {
    final image = await _decode(bytes);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) {
        throw StateError('Unable to read selfie pixels.');
      }
      final pixels = data.buffer.asUint8List();
      final hash = _averageHash(pixels);
      final histogram = _colorHistogram(pixels);
      return 'v1:$hash:${histogram.join(',')}';
    } finally {
      image.dispose();
    }
  }

  FaceMatchResult compare({
    required String referenceSignature,
    required String selfieSignature,
  }) {
    final reference = _ParsedSignature.tryParse(referenceSignature);
    final selfie = _ParsedSignature.tryParse(selfieSignature);
    if (reference == null || selfie == null) {
      return const FaceMatchResult(passed: false, score: 0);
    }

    final hashSimilarity = _hashSimilarity(reference.hash, selfie.hash);
    final histogramSimilarity =
        _histogramSimilarity(reference.histogram, selfie.histogram);
    final score = (hashSimilarity * 0.45) + (histogramSimilarity * 0.55);
    return FaceMatchResult(
      passed: score >= passThreshold,
      score: score.clamp(0, 1).toDouble(),
    );
  }

  Future<ui.Image> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 32,
      targetHeight: 32,
    );
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  String _averageHash(Uint8List pixels) {
    final luminance = <int>[];
    for (var i = 0; i < pixels.length; i += 4) {
      final r = pixels[i];
      final g = pixels[i + 1];
      final b = pixels[i + 2];
      luminance.add(((r * 299) + (g * 587) + (b * 114)) ~/ 1000);
    }
    final average =
        luminance.fold<int>(0, (sum, value) => sum + value) / luminance.length;
    final buffer = StringBuffer();
    for (final value in luminance) {
      buffer.write(value >= average ? '1' : '0');
    }
    return buffer.toString();
  }

  List<int> _colorHistogram(Uint8List pixels) {
    final buckets = List<int>.filled(64, 0);
    for (var i = 0; i < pixels.length; i += 4) {
      final rBucket = pixels[i] ~/ 64;
      final gBucket = pixels[i + 1] ~/ 64;
      final bBucket = pixels[i + 2] ~/ 64;
      buckets[(rBucket * 16) + (gBucket * 4) + bBucket]++;
    }
    return buckets;
  }

  double _hashSimilarity(String left, String right) {
    final length = math.min(left.length, right.length);
    if (length == 0) return 0;
    var matches = 0;
    for (var i = 0; i < length; i++) {
      if (left.codeUnitAt(i) == right.codeUnitAt(i)) matches++;
    }
    return matches / length;
  }

  double _histogramSimilarity(List<int> left, List<int> right) {
    final length = math.min(left.length, right.length);
    if (length == 0) return 0;
    var overlap = 0;
    var total = 0;
    for (var i = 0; i < length; i++) {
      overlap += math.min(left[i], right[i]);
      total += math.max(left[i], right[i]);
    }
    if (total == 0) return 0;
    return overlap / total;
  }
}

class _ParsedSignature {
  const _ParsedSignature({
    required this.hash,
    required this.histogram,
  });

  final String hash;
  final List<int> histogram;

  static _ParsedSignature? tryParse(String value) {
    final parts = value.split(':');
    if (parts.length != 3 || parts.first != 'v1') return null;
    final histogram = parts[2]
        .split(',')
        .map((item) => int.tryParse(item))
        .whereType<int>()
        .toList();
    if (parts[1].isEmpty || histogram.isEmpty) return null;
    return _ParsedSignature(hash: parts[1], histogram: histogram);
  }
}
