import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as image_lib;
import 'package:onnxruntime/onnxruntime.dart';

import '../application/recognition_draft_use_cases.dart';
import '../domain/tile.dart';
import '../domain/tile_recognition.dart';

/// 同梱したYOLO ONNXモデルで牌を端末内認識します。
class OnnxMahjongTileRecognizer implements MahjongTileRecognizer {
  /// 端末内認識器を生成します。
  OnnxMahjongTileRecognizer({
    this.confidenceThreshold = 0.30,
    this.iouThreshold = 0.50,
  });

  /// 検出候補として残す最低信頼度です。
  final double confidenceThreshold;

  /// 重複する検出枠を除外するIoU基準です。
  final double iouThreshold;

  /// 推論セッションの設定です。
  OrtSessionOptions? _sessionOptions;

  /// 同梱モデルを読み込んだ推論セッションです。
  OrtSession? _session;

  /// 同梱モデルのFlutterアセットパスです。
  static const modelAssetPath = 'assets/models/mahjong-yolon-best.onnx';

  /// 出典コミットを含む表示用モデル版です。
  static const modelVersion = 'Mahjong-YOLO nano 28ffceed';

  /// YOLOモデルへ入力する正方形画像の一辺です。
  static const _modelSize = 640;

  /// モデル出力のクラス順です。
  static const _classNames = <String>[
    '1m',
    '1p',
    '1s',
    '1z',
    '2m',
    '2p',
    '2s',
    '2z',
    '3m',
    '3p',
    '3s',
    '3z',
    '4m',
    '4p',
    '4s',
    '4z',
    '5m',
    '5p',
    '5s',
    '5z',
    '6m',
    '6p',
    '6s',
    '6z',
    '7m',
    '7p',
    '7s',
    '7z',
    '8m',
    '8p',
    '8s',
    '9m',
    '9p',
    '9s',
    'UNKNOWN',
    '0m',
    '0p',
    '0s',
  ];

  @override
  Future<TileRecognitionResult> recognize(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    final prepared = await Isolate.run(() => _prepareImage(bytes));
    final session = await _ensureSession();
    final input = OrtValueTensor.createTensorWithDataList(
      prepared.tensor,
      const [1, 3, _modelSize, _modelSize],
    );
    final runOptions = OrtRunOptions();
    List<OrtValue?>? outputs;
    try {
      final asynchronous = session.runAsync(runOptions, {
        session.inputNames.first: input,
      });
      outputs = asynchronous == null
          ? session.run(runOptions, {session.inputNames.first: input})
          : await asynchronous;
      if (outputs.isEmpty || outputs.first?.value == null) {
        throw const FormatException('認識モデルの出力がありません。');
      }
      final value = outputs.first!.value;
      if (value is! List || value.isEmpty || value.first is! List) {
        throw const FormatException('認識モデルの出力形式が不正です。');
      }
      final batch = value.first as List;
      final channels = batch.length;
      if (channels != _classNames.length + 4 || batch.first is! List) {
        throw FormatException('認識モデルのクラス数が不正です: $channels');
      }
      final anchors = (batch.first as List).length;
      final candidates = _decode(
        batch: batch,
        anchors: anchors,
        prepared: prepared,
      );
      return TileRecognitionResult(
        imageWidth: prepared.originalWidth,
        imageHeight: prepared.originalHeight,
        tiles: List.unmodifiable(candidates),
        modelVersion: modelVersion,
      );
    } finally {
      input.release();
      runOptions.release();
      outputs?.forEach((output) => output?.release());
    }
  }

  /// 初回利用時に同梱モデルを読み込み、以後の撮影で再利用します。
  Future<OrtSession> _ensureSession() async {
    final cached = _session;
    if (cached != null) return cached;
    OrtEnv.instance.init();
    final options = OrtSessionOptions()
      ..setInterOpNumThreads(1)
      ..setIntraOpNumThreads(2)
      ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);
    final asset = await rootBundle.load(modelAssetPath);
    final bytes = asset.buffer.asUint8List(
      asset.offsetInBytes,
      asset.lengthInBytes,
    );
    _sessionOptions = options;
    return _session = OrtSession.fromBuffer(bytes, options);
  }

  /// YOLO出力を座標付き牌候補へ変換し、重複枠を除外します。
  List<RecognizedTile> _decode({
    required List batch,
    required int anchors,
    required _PreparedImage prepared,
  }) {
    final boxes = <_ScoredBox>[];
    for (var anchor = 0; anchor < anchors; anchor++) {
      var bestScore = -double.infinity;
      var bestClass = -1;
      for (var classIndex = 0; classIndex < _classNames.length; classIndex++) {
        final score = ((batch[4 + classIndex] as List)[anchor] as num)
            .toDouble();
        if (score > bestScore) {
          bestScore = score;
          bestClass = classIndex;
        }
      }
      if (bestScore < confidenceThreshold) continue;
      boxes.add(
        _ScoredBox(
          centerX: ((batch[0] as List)[anchor] as num).toDouble(),
          centerY: ((batch[1] as List)[anchor] as num).toDouble(),
          width: ((batch[2] as List)[anchor] as num).toDouble(),
          height: ((batch[3] as List)[anchor] as num).toDouble(),
          confidence: bestScore,
          classIndex: bestClass,
        ),
      );
    }
    boxes.sort(
      (first, second) => second.confidence.compareTo(first.confidence),
    );
    final kept = <_ScoredBox>[];
    for (final candidate in boxes) {
      if (kept.any((accepted) => _iou(candidate, accepted) > iouThreshold)) {
        continue;
      }
      kept.add(candidate);
    }
    return [
      for (var index = 0; index < kept.length; index++)
        _toRecognizedTile(kept[index], prepared, index),
    ];
  }

  /// モデル入力座標を元画像の正規化座標へ戻します。
  RecognizedTile _toRecognizedTile(
    _ScoredBox box,
    _PreparedImage prepared,
    int index,
  ) {
    final left = (box.centerX - box.width / 2 - prepared.padX) / prepared.scale;
    final top = (box.centerY - box.height / 2 - prepared.padY) / prepared.scale;
    final width = box.width / prepared.scale;
    final height = box.height / prepared.scale;
    return RecognizedTile(
      id: 'detected-$index',
      tile: _tileForClass(_classNames[box.classIndex]),
      boundingBox: NormalizedRect(
        left: left / prepared.originalWidth,
        top: top / prepared.originalHeight,
        width: width / prepared.originalWidth,
        height: height / prepared.originalHeight,
      ).clamped(),
      confidence: box.confidence,
      region: RecognitionRegion.unknown,
    );
  }

  @override
  void dispose() {
    _session?.release();
    _session = null;
    _sessionOptions?.release();
    _sessionOptions = null;
    OrtEnv.instance.release();
  }
}

/// 画像を640角へレターボックス変換し、RGBのCHW配列を返します。
_PreparedImage _prepareImage(Uint8List bytes) {
  final decoded = image_lib.decodeImage(bytes);
  if (decoded == null) throw const FormatException('画像を読み込めません。');
  final source = image_lib.bakeOrientation(decoded);
  final scale = math.min(
    OnnxMahjongTileRecognizer._modelSize / source.width,
    OnnxMahjongTileRecognizer._modelSize / source.height,
  );
  final resizedWidth = math.max(1, (source.width * scale).round());
  final resizedHeight = math.max(1, (source.height * scale).round());
  final resized = image_lib.copyResize(
    source,
    width: resizedWidth,
    height: resizedHeight,
    interpolation: image_lib.Interpolation.linear,
  );
  final padX = (OnnxMahjongTileRecognizer._modelSize - resizedWidth) ~/ 2;
  final padY = (OnnxMahjongTileRecognizer._modelSize - resizedHeight) ~/ 2;
  final plane =
      OnnxMahjongTileRecognizer._modelSize *
      OnnxMahjongTileRecognizer._modelSize;
  final tensor = Float32List(plane * 3)..fillRange(0, plane * 3, 114 / 255);
  for (final pixel in resized) {
    final destination =
        (pixel.y + padY) * OnnxMahjongTileRecognizer._modelSize +
        pixel.x +
        padX;
    tensor[destination] = pixel.r / 255;
    tensor[plane + destination] = pixel.g / 255;
    tensor[plane * 2 + destination] = pixel.b / 255;
  }
  return _PreparedImage(
    tensor: tensor,
    originalWidth: source.width,
    originalHeight: source.height,
    scale: scale,
    padX: padX.toDouble(),
    padY: padY.toDouble(),
  );
}

/// モデルへ渡した配列と元画像へ座標を戻す情報です。
class _PreparedImage {
  /// 前処理結果を生成します。
  const _PreparedImage({
    required this.tensor,
    required this.originalWidth,
    required this.originalHeight,
    required this.scale,
    required this.padX,
    required this.padY,
  });

  /// RGBをCHW順に並べた入力値です。
  final Float32List tensor;

  /// EXIFの向きを反映した元画像幅です。
  final int originalWidth;

  /// EXIFの向きを反映した元画像高です。
  final int originalHeight;

  /// 元画像からモデル入力へ拡縮した倍率です。
  final double scale;

  /// モデル入力の左側へ追加した余白です。
  final double padX;

  /// モデル入力の上側へ追加した余白です。
  final double padY;
}

/// NMS前のYOLO検出枠です。
class _ScoredBox {
  /// 検出枠を生成します。
  const _ScoredBox({
    required this.centerX,
    required this.centerY,
    required this.width,
    required this.height,
    required this.confidence,
    required this.classIndex,
  });

  /// 枠中央の横座標です。
  final double centerX;

  /// 枠中央の縦座標です。
  final double centerY;

  /// 枠の幅です。
  final double width;

  /// 枠の高さです。
  final double height;

  /// 最上位クラスの信頼度です。
  final double confidence;

  /// 最上位クラスの出力番号です。
  final int classIndex;
}

/// 二つの検出枠が重なる割合を返します。
double _iou(_ScoredBox first, _ScoredBox second) {
  final firstLeft = first.centerX - first.width / 2;
  final firstTop = first.centerY - first.height / 2;
  final firstRight = first.centerX + first.width / 2;
  final firstBottom = first.centerY + first.height / 2;
  final secondLeft = second.centerX - second.width / 2;
  final secondTop = second.centerY - second.height / 2;
  final secondRight = second.centerX + second.width / 2;
  final secondBottom = second.centerY + second.height / 2;
  final overlapWidth = math.max(
    0.0,
    math.min(firstRight, secondRight) - math.max(firstLeft, secondLeft),
  );
  final overlapHeight = math.max(
    0.0,
    math.min(firstBottom, secondBottom) - math.max(firstTop, secondTop),
  );
  final intersection = overlapWidth * overlapHeight;
  final union =
      first.width * first.height + second.width * second.height - intersection;
  return union <= 0 ? 0 : intersection / union;
}

/// モデルのクラス名を既存34種へ変換します。
Tile? _tileForClass(String name) {
  if (name == 'UNKNOWN') return null;
  final normalized = switch (name) {
    '0m' => '5m',
    '0p' => '5p',
    '0s' => '5s',
    _ => name,
  };
  final number = int.tryParse(normalized[0]);
  if (number == null) return null;
  return switch (normalized[1]) {
    'm' => Tile.values[number - 1],
    'p' => Tile.values[9 + number - 1],
    's' => Tile.values[18 + number - 1],
    'z' when number >= 1 && number <= 7 => Tile.values[27 + number - 1],
    _ => null,
  };
}
