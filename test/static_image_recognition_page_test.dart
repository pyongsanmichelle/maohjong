import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;
import 'package:maohjong/application/image_source_gateway.dart';
import 'package:maohjong/application/recognition_draft_use_cases.dart';
import 'package:maohjong/domain/tile.dart';
import 'package:maohjong/domain/tile_recognition.dart';
import 'package:maohjong/main.dart';
import 'package:maohjong/presentation/static_image_recognition_page.dart';

void main() {
  late File imageFile;

  setUp(() {
    imageFile = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'maohjong-recognition-${DateTime.now().microsecondsSinceEpoch}.png',
    );
    imageFile.writeAsBytesSync(
      image_lib.encodePng(image_lib.Image(width: 8, height: 6)),
    );
  });

  tearDown(() {
    if (imageFile.existsSync()) imageFile.deleteSync();
  });

  testWidgets('認識中表示から候補確認と確定へ進める', (tester) async {
    final recognizer = _ControllableRecognizer([
      _candidate('hand', Tile.m1, RecognitionRegion.ownHand),
      _candidate('dora', Tile.p9, RecognitionRegion.doraIndicators),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: StaticImageRecognitionPage(
          imagePath: imageFile.path,
          recognizer: recognizer,
        ),
      ),
    );

    expect(find.byKey(const Key('recognitionProgress')), findsOneWidget);
    recognizer.complete();
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('recognitionReviewList')),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recognitionRegion-ownHand')), findsOneWidget);
    expect(
      find.byKey(const Key('recognitionRegion-doraIndicators')),
      findsOneWidget,
    );
    final apply = tester.widget<FilledButton>(
      find.byKey(const Key('recognitionApplyButton')),
    );
    expect(apply.onPressed, isNotNull);
  });

  testWidgets('未確定の牌がある間は局面へ反映できない', (tester) async {
    final recognizer = _ControllableRecognizer([
      _candidate('unknown', null, RecognitionRegion.ownHand),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: StaticImageRecognitionPage(
          imagePath: imageFile.path,
          recognizer: recognizer,
        ),
      ),
    );
    recognizer.complete();
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('recognitionReviewList')),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('要確認'), findsOneWidget);
    final apply = tester.widget<FilledButton>(
      find.byKey(const Key('recognitionApplyButton')),
    );
    expect(apply.onPressed, isNull);
  });

  testWidgets('準備画面で画像を選び確認した候補だけを局面へ反映する', (tester) async {
    final recognizer = _FakeRecognizer([
      _candidate('hand', Tile.m1, RecognitionRegion.ownHand),
      _candidate('dora', Tile.p9, RecognitionRegion.doraIndicators),
    ]);
    await tester.pumpWidget(
      MaohjongApp(
        imageSourceGateway: _FakeImageSourceGateway(imageFile.path),
        tileRecognizer: recognizer,
      ),
    );
    await tester.pumpAndSettle();

    final importButton = find.byKey(const Key('staticImageInputButton'));
    await tester.ensureVisible(importButton);
    await tester.tap(importButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('recognitionGallerySource')));
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('recognitionApplyButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('handTile-0')), findsOneWidget);
    expect(find.byKey(const Key('setupDoraTile-0')), findsOneWidget);
    expect(find.textContaining('確認済みの認識結果'), findsOneWidget);
  });
}

/// Widgetテスト用の確定済み認識候補を生成します。
RecognizedTile _candidate(String id, Tile? tile, RecognitionRegion region) =>
    RecognizedTile(
      id: id,
      tile: tile,
      boundingBox: const NormalizedRect(
        left: 0.1,
        top: 0.1,
        width: 0.1,
        height: 0.1,
      ),
      confidence: 0.95,
      region: region,
    );

/// 固定の候補を返すテスト用認識器です。
class _FakeRecognizer implements MahjongTileRecognizer {
  /// 返却する候補を受け取ります。
  _FakeRecognizer(this.tiles);

  /// 認識結果として返す候補です。
  final List<RecognizedTile> tiles;

  @override
  Future<TileRecognitionResult> recognize(String imagePath) async =>
      TileRecognitionResult(
        imageWidth: 8,
        imageHeight: 6,
        tiles: tiles,
        modelVersion: 'fake-model',
      );

  @override
  void dispose() {}
}

/// テスト側の明示操作で認識完了を通知する認識器です。
class _ControllableRecognizer implements MahjongTileRecognizer {
  /// 完了時に返す候補を受け取ります。
  _ControllableRecognizer(this.tiles);

  /// 認識結果として返す候補です。
  final List<RecognizedTile> tiles;

  /// UIが認識開始した後に完了させるための待機結果です。
  final Completer<TileRecognitionResult> _completer = Completer();

  /// 待機中の認識を完了します。
  void complete() => _completer.complete(
    TileRecognitionResult(
      imageWidth: 8,
      imageHeight: 6,
      tiles: tiles,
      modelVersion: 'fake-model',
    ),
  );

  @override
  Future<TileRecognitionResult> recognize(String imagePath) =>
      _completer.future;

  @override
  void dispose() {}
}

/// 常に同じ画像パスを返すテスト用画像取得処理です。
class _FakeImageSourceGateway implements ImageSourceGateway {
  /// 返却する画像パスを受け取ります。
  const _FakeImageSourceGateway(this.path);

  /// 取得済み画像のパスです。
  final String path;

  @override
  Future<ImageAcquisitionResult> acquire(StillImageSource source) async =>
      ImageAcquisitionResult.success(path);

  @override
  Future<ImageAcquisitionResult?> retrieveLostImage() async => null;
}
