import 'dart:async';
import 'dart:developer' as developer;
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
import 'yolo_output_tensor.dart';

/// 同梱したYOLO ONNXモデルで牌を端末内認識します。
class OnnxMahjongTileRecognizer
    implements MahjongTileRecognizer, CancellableMahjongTileRecognizer {
  /// 端末内認識器を生成します。
  OnnxMahjongTileRecognizer({
    this.confidenceThreshold = 0.40,
    this.iouThreshold = 0.50,
    this.inferenceTimeout = const Duration(seconds: 25),
  });

  /// 検出候補として残す最低信頼度です。
  final double confidenceThreshold;

  /// 重複する検出枠を除外するIoU基準です。
  final double iouThreshold;

  /// ワーカーIsolateの応答を待つ最大時間です。
  final Duration inferenceTimeout;

  /// 現在実行中の認識ジョブです。
  _ActiveRecognition? _activeRecognition;

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
    '0m',
    '0p',
    '0s',
  ];

  @override
  Future<TileRecognitionResult> recognize(String imagePath) async {
    cancelActiveRecognition();
    final stopwatch = Stopwatch()..start();
    final active = _ActiveRecognition();
    _activeRecognition = active;
    unawaited(
      active.completer.future.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      ),
    );
    active.messageSubscription = active.messages.listen((message) {
      if (message is _WorkerStage) {
        active.stage = message.name;
      } else if (message is _WorkerSuccess) {
        if (!active.completer.isCompleted) {
          active.completer.complete(message.result);
        }
      } else if (message is _WorkerFailure) {
        developer.log(
          'failed stage=${message.stage} type=${message.errorType} '
          'code=${message.errorCode} '
          'elapsedMs=${stopwatch.elapsedMilliseconds}',
          name: 'maohjong.static_image_recognition',
        );
        if (!active.completer.isCompleted) {
          active.completer.completeError(
            RecognitionInferenceException(message.stage),
          );
        }
      }
    });
    active.errorSubscription = active.errors.listen((message) {
      developer.log(
        'worker_error stage=${active.stage} '
        'elapsedMs=${stopwatch.elapsedMilliseconds}',
        name: 'maohjong.static_image_recognition',
      );
      if (!active.completer.isCompleted) {
        active.completer.completeError(
          RecognitionInferenceException(active.stage),
        );
      }
    });
    active.timer = Timer(inferenceTimeout, () {
      developer.log(
        'timeout stage=${active.stage} '
        'elapsedMs=${stopwatch.elapsedMilliseconds}',
        name: 'maohjong.static_image_recognition',
      );
      active.cancel(RecognitionInferenceTimeout(active.stage));
    });
    try {
      active.stage = 'image_loading';
      final imageBytes = await File(imagePath).readAsBytes();
      if (active.cancelled) throw const RecognitionInferenceCancelled();
      active.stage = 'model_asset_loading';
      final modelAsset = await rootBundle.load(modelAssetPath);
      final modelBytes = modelAsset.buffer.asUint8List(
        modelAsset.offsetInBytes,
        modelAsset.lengthInBytes,
      );
      if (active.cancelled) throw const RecognitionInferenceCancelled();
      active.isolate = await Isolate.spawn(
        _recognitionWorkerMain,
        _WorkerRequest(
          replyTo: active.messages.sendPort,
          imageBytes: TransferableTypedData.fromList([imageBytes]),
          modelBytes: TransferableTypedData.fromList([modelBytes]),
          confidenceThreshold: confidenceThreshold,
          iouThreshold: iouThreshold,
        ),
        onError: active.errors.sendPort,
        errorsAreFatal: true,
        debugName: 'MahjongRecognitionWorker',
      );
      if (active.cancelled) {
        active.isolate?.kill(priority: Isolate.immediate);
      }
      final result = await active.completer.future;
      developer.log(
        'completed detections=${result.tiles.length} '
        'elapsedMs=${stopwatch.elapsedMilliseconds}',
        name: 'maohjong.static_image_recognition',
      );
      return result;
    } finally {
      stopwatch.stop();
      await active.close();
      if (identical(_activeRecognition, active)) {
        _activeRecognition = null;
      }
    }
  }

  @override
  void cancelActiveRecognition() {
    _activeRecognition?.cancel(const RecognitionInferenceCancelled());
  }

  /// YOLO出力を座標付き牌候補へ変換し、重複枠を除外します。
  List<RecognizedTile> _decode({
    required YoloOutputTensor output,
    required _PreparedImage prepared,
  }) {
    final boxes = <_ScoredBox>[];
    for (var anchor = 0; anchor < output.anchorCount; anchor++) {
      var bestScore = -double.infinity;
      var bestClass = -1;
      for (var classIndex = 0; classIndex < _classNames.length; classIndex++) {
        final score = output.valueAt(4 + classIndex, anchor);
        if (score > bestScore) {
          bestScore = score;
          bestClass = classIndex;
        }
      }
      if (bestScore < confidenceThreshold) continue;
      boxes.add(
        _ScoredBox(
          centerX: output.valueAt(0, anchor),
          centerY: output.valueAt(1, anchor),
          width: output.valueAt(2, anchor),
          height: output.valueAt(3, anchor),
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
      if (kept.any(
        (accepted) =>
            _iou(candidate, accepted) > iouThreshold ||
            _overlapOverSmallerArea(candidate, accepted) > 0.65 ||
            _hasSamePhysicalCenter(candidate, accepted),
      )) {
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
  void dispose() => cancelActiveRecognition();
}

/// 認識ワーカーを所有し、完了・中断時の資源解放を一元化します。
class _ActiveRecognition {
  /// ワーカーからの進捗と結果を受け取るポートです。
  final messages = ReceivePort();

  /// ワーカーの未処理例外を受け取るポートです。
  final errors = ReceivePort();

  /// 呼び出し元へ返す認識結果です。
  final completer = Completer<TileRecognitionResult>();

  /// 実行中のワーカーIsolateです。
  Isolate? isolate;

  /// 通常メッセージの購読です。
  StreamSubscription<dynamic>? messageSubscription;

  /// エラーメッセージの購読です。
  StreamSubscription<dynamic>? errorSubscription;

  /// 応答待ちを打ち切るタイマーです。
  Timer? timer;

  /// 診断用の現在処理段階です。
  var stage = 'starting';

  /// 中断済みかどうかです。
  var cancelled = false;

  /// 待機Futureを失敗させ、ワーカーを即時停止します。
  void cancel(Object error) {
    if (cancelled) return;
    cancelled = true;
    if (!completer.isCompleted) completer.completeError(error);
    isolate?.kill(priority: Isolate.immediate);
  }

  /// ジョブに紐づくDart資源を解放します。
  Future<void> close() async {
    timer?.cancel();
    isolate?.kill(priority: Isolate.immediate);
    await messageSubscription?.cancel();
    await errorSubscription?.cancel();
    messages.close();
    errors.close();
  }
}

/// ワーカーIsolateへ渡す、ネイティブ資源を含まない入力です。
class _WorkerRequest {
  /// 認識入力を生成します。
  const _WorkerRequest({
    required this.replyTo,
    required this.imageBytes,
    required this.modelBytes,
    required this.confidenceThreshold,
    required this.iouThreshold,
  });

  /// 進捗と結果を返すポートです。
  final SendPort replyTo;

  /// 転送可能な撮影画像です。
  final TransferableTypedData imageBytes;

  /// 転送可能なONNXモデルです。
  final TransferableTypedData modelBytes;

  /// 候補として残す最低信頼度です。
  final double confidenceThreshold;

  /// 重複検出を除くIoU基準です。
  final double iouThreshold;
}

/// ワーカーの処理段階通知です。
class _WorkerStage {
  /// 処理段階を生成します。
  const _WorkerStage(this.name);

  /// 個人情報を含まない段階名です。
  final String name;
}

/// ワーカーの認識成功通知です。
class _WorkerSuccess {
  /// 成功結果を生成します。
  const _WorkerSuccess(this.result);

  /// ネイティブ資源を含まない認識結果です。
  final TileRecognitionResult result;
}

/// ワーカーの認識失敗通知です。
class _WorkerFailure {
  /// 安全な診断情報だけを持つ失敗結果を生成します。
  const _WorkerFailure(this.stage, this.errorType, this.errorCode);

  /// 失敗した処理段階です。
  final String stage;

  /// パスや画像内容を含まない例外型です。
  final String errorType;

  /// 推論値や画像内容を含まない構造化エラーコードです。
  final String errorCode;
}

/// ONNX資源をワーカー内だけで生成・利用・解放して牌を認識します。
@pragma('vm:entry-point')
void _recognitionWorkerMain(_WorkerRequest request) {
  var stage = 'preprocessing';
  OrtSessionOptions? options;
  OrtSession? session;
  OrtValueTensor? input;
  OrtRunOptions? runOptions;
  List<OrtValue?>? outputs;
  TileRecognitionResult? result;
  var environmentInitialized = false;
  try {
    request.replyTo.send(_WorkerStage(stage));
    final prepared = _prepareImage(
      request.imageBytes.materialize().asUint8List(),
    );
    stage = 'model_loading';
    request.replyTo.send(_WorkerStage(stage));
    OrtEnv.instance.init();
    environmentInitialized = true;
    options = OrtSessionOptions()
      ..setInterOpNumThreads(1)
      ..setIntraOpNumThreads(2)
      ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);
    session = OrtSession.fromBuffer(
      request.modelBytes.materialize().asUint8List(),
      options,
    );
    stage = 'inference';
    request.replyTo.send(_WorkerStage(stage));
    input = OrtValueTensor.createTensorWithDataList(prepared.tensor, const [
      1,
      3,
      OnnxMahjongTileRecognizer._modelSize,
      OnnxMahjongTileRecognizer._modelSize,
    ]);
    runOptions = OrtRunOptions();
    outputs = session.run(runOptions, {session.inputNames.first: input});
    stage = 'postprocessing';
    request.replyTo.send(_WorkerStage(stage));
    if (outputs.isEmpty || outputs.first?.value == null) {
      throw const FormatException('empty_output');
    }
    final output = YoloOutputTensor.parse(
      outputs.first!.value,
      channelCount: OnnxMahjongTileRecognizer._classNames.length + 4,
    );
    final recognizer = OnnxMahjongTileRecognizer(
      confidenceThreshold: request.confidenceThreshold,
      iouThreshold: request.iouThreshold,
    );
    final candidates = recognizer._decode(output: output, prepared: prepared);
    result = TileRecognitionResult(
      imageWidth: prepared.originalWidth,
      imageHeight: prepared.originalHeight,
      tiles: List.unmodifiable(candidates),
      modelVersion: OnnxMahjongTileRecognizer.modelVersion,
    );
  } catch (error) {
    final errorCode = error is FormatException
        ? error.message.toString()
        : 'unexpected_error';
    request.replyTo.send(
      _WorkerFailure(stage, error.runtimeType.toString(), errorCode),
    );
  } finally {
    for (final output in outputs ?? const <OrtValue?>[]) {
      try {
        output?.release();
      } catch (_) {}
    }
    try {
      input?.release();
    } catch (_) {}
    try {
      runOptions?.release();
    } catch (_) {}
    try {
      session?.release();
    } catch (_) {}
    try {
      options?.release();
    } catch (_) {}
    if (environmentInitialized) {
      try {
        OrtEnv.instance.release();
      } catch (_) {}
    }
  }
  if (result != null) request.replyTo.send(_WorkerSuccess(result));
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
  final overlap = _overlap(first, second);
  final union =
      first.width * first.height + second.width * second.height - overlap;
  return union <= 0 ? 0 : overlap / union;
}

/// 小さい方の検出枠に対する重複割合を返します。
double _overlapOverSmallerArea(_ScoredBox first, _ScoredBox second) {
  final smallerArea = math.min(
    first.width * first.height,
    second.width * second.height,
  );
  return smallerArea <= 0 ? 0 : _overlap(first, second) / smallerArea;
}

/// 枠サイズに対して中心がほぼ同じ二候補を同一牌として扱います。
bool _hasSamePhysicalCenter(_ScoredBox first, _ScoredBox second) {
  final horizontalTolerance = math.min(first.width, second.width) * 0.25;
  final verticalTolerance = math.min(first.height, second.height) * 0.25;
  return (first.centerX - second.centerX).abs() <= horizontalTolerance &&
      (first.centerY - second.centerY).abs() <= verticalTolerance;
}

/// 二つの検出枠が重なる面積を返します。
double _overlap(_ScoredBox first, _ScoredBox second) {
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
  return overlapWidth * overlapHeight;
}

/// モデルのクラス名を既存34種へ変換します。
Tile? _tileForClass(String name) {
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
