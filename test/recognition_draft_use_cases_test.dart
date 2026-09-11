import 'package:flutter_test/flutter_test.dart';
import 'package:maohjong/application/recognition_draft_use_cases.dart';
import 'package:maohjong/domain/game_situation.dart';
import 'package:maohjong/domain/tile.dart';
import 'package:maohjong/domain/tile_recognition.dart';

void main() {
  const builder = BuildRecognitionDraftUseCase();

  test('画像上の位置から手牌・河・ドラへ初期配置する', () {
    final draft = builder(
      imagePath: 'table.jpg',
      result: const TileRecognitionResult(
        imageWidth: 1000,
        imageHeight: 800,
        modelVersion: 'test-model',
        tiles: [
          RecognizedTile(
            id: 'hand',
            tile: Tile.m1,
            boundingBox: NormalizedRect(
              left: 0.4,
              top: 0.82,
              width: 0.08,
              height: 0.12,
            ),
            confidence: 0.9,
            region: RecognitionRegion.unknown,
          ),
          RecognizedTile(
            id: 'upper',
            tile: Tile.p2,
            boundingBox: NormalizedRect(
              left: 0.1,
              top: 0.4,
              width: 0.08,
              height: 0.12,
            ),
            confidence: 0.9,
            region: RecognitionRegion.unknown,
          ),
          RecognizedTile(
            id: 'dora',
            tile: Tile.s3,
            boundingBox: NormalizedRect(
              left: 0.47,
              top: 0.47,
              width: 0.05,
              height: 0.05,
            ),
            confidence: 0.9,
            region: RecognitionRegion.unknown,
          ),
        ],
      ),
    );

    expect(_regionOf(draft, 'hand'), RecognitionRegion.ownHand);
    expect(_regionOf(draft, 'upper'), RecognitionRegion.upperRiver);
    expect(_regionOf(draft, 'dora'), RecognitionRegion.doraIndicators);
    expect(draft.canApply, isTrue);
  });

  test('画像の最下段へ達する牌は中心が河の範囲でも自分の手牌にする', () {
    final draft = builder(
      imagePath: 'table.jpg',
      result: const TileRecognitionResult(
        imageWidth: 1000,
        imageHeight: 800,
        modelVersion: 'test-model',
        tiles: [
          RecognizedTile(
            id: 'front-hand',
            tile: Tile.m1,
            boundingBox: NormalizedRect(
              left: 0.4,
              top: 0.67,
              width: 0.08,
              height: 0.14,
            ),
            confidence: 0.9,
            region: RecognitionRegion.unknown,
          ),
          RecognizedTile(
            id: 'own-river',
            tile: Tile.p2,
            boundingBox: NormalizedRect(
              left: 0.4,
              top: 0.61,
              width: 0.08,
              height: 0.10,
            ),
            confidence: 0.9,
            region: RecognitionRegion.unknown,
          ),
        ],
      ),
    );

    expect(_regionOf(draft, 'front-hand'), RecognitionRegion.ownHand);
    expect(_regionOf(draft, 'own-river'), RecognitionRegion.ownRiver);
  });

  test('撮影角度で下端が固定境界に届かなくても最下段の横並びを手牌にする', () {
    final detected = <RecognizedTile>[
      for (var index = 0; index < 3; index++)
        RecognizedTile(
          id: 'hand-$index',
          tile: Tile.values[index],
          boundingBox: NormalizedRect(
            left: 0.25 + index * 0.10,
            top: 0.62,
            width: 0.08,
            height: 0.13,
          ),
          confidence: 0.9,
          region: RecognitionRegion.unknown,
        ),
      const RecognizedTile(
        id: 'river',
        tile: Tile.p1,
        boundingBox: NormalizedRect(
          left: 0.46,
          top: 0.58,
          width: 0.07,
          height: 0.08,
        ),
        confidence: 0.9,
        region: RecognitionRegion.unknown,
      ),
    ];
    final draft = builder(
      imagePath: 'table.jpg',
      result: TileRecognitionResult(
        imageWidth: 1000,
        imageHeight: 800,
        modelVersion: 'test-model',
        tiles: detected,
      ),
    );

    for (var index = 0; index < 3; index++) {
      expect(_regionOf(draft, 'hand-$index'), RecognitionRegion.ownHand);
    }
    expect(_regionOf(draft, 'river'), RecognitionRegion.ownRiver);
  });

  test('中央付近でも通常サイズの対面牌をドラ表示牌にしない', () {
    final draft = builder(
      imagePath: 'table.jpg',
      result: const TileRecognitionResult(
        imageWidth: 1000,
        imageHeight: 800,
        modelVersion: 'test-model',
        tiles: [
          RecognizedTile(
            id: 'across-discard',
            tile: Tile.m1,
            boundingBox: NormalizedRect(
              left: 0.46,
              top: 0.39,
              width: 0.08,
              height: 0.12,
            ),
            confidence: 0.9,
            region: RecognitionRegion.unknown,
          ),
          RecognizedTile(
            id: 'dora',
            tile: Tile.p2,
            boundingBox: NormalizedRect(
              left: 0.47,
              top: 0.47,
              width: 0.05,
              height: 0.05,
            ),
            confidence: 0.9,
            region: RecognitionRegion.unknown,
          ),
        ],
      ),
    );

    expect(_regionOf(draft, 'across-discard'), RecognitionRegion.acrossRiver);
    expect(_regionOf(draft, 'dora'), RecognitionRegion.doraIndicators);
  });

  test('低信頼度は警告するが未確定牌と配置不明だけが反映を妨げる', () {
    final lowConfidence = builder.rebuild(
      imagePath: 'table.jpg',
      imageWidth: 1,
      imageHeight: 1,
      tiles: [_candidate('low', Tile.m1, RecognitionRegion.ownHand, 0.2)],
      modelVersion: 'test-model',
    );
    final unknown = builder.rebuild(
      imagePath: 'table.jpg',
      imageWidth: 1,
      imageHeight: 1,
      tiles: [_candidate('unknown', null, RecognitionRegion.unknown, 0.9)],
      modelVersion: 'test-model',
    );

    expect(
      lowConfidence.issues.single.type,
      RecognitionIssueType.lowConfidence,
    );
    expect(lowConfidence.canApply, isTrue);
    expect(
      unknown.issues.map((issue) => issue.type),
      containsAll([
        RecognitionIssueType.unknownTile,
        RecognitionIssueType.unknownRegion,
      ]),
    );
    expect(unknown.canApply, isFalse);
  });

  test('同一牌5枚と手牌15枚は反映前に検出する', () {
    final tooManyCopies = builder.rebuild(
      imagePath: 'table.jpg',
      imageWidth: 1,
      imageHeight: 1,
      tiles: [
        for (var index = 0; index < 5; index++)
          _candidate('$index', Tile.east, RecognitionRegion.ownRiver, 0.9),
      ],
      modelVersion: 'test-model',
    );
    final tooManyHand = builder.rebuild(
      imagePath: 'table.jpg',
      imageWidth: 1,
      imageHeight: 1,
      tiles: [
        for (var index = 0; index < 15; index++)
          _candidate(
            '$index',
            Tile.values[index],
            RecognitionRegion.ownHand,
            0.9,
          ),
      ],
      modelVersion: 'test-model',
    );

    expect(
      tooManyCopies.issues.map((issue) => issue.type),
      contains(RecognitionIssueType.tooManyCopies),
    );
    expect(
      tooManyHand.issues.map((issue) => issue.type),
      contains(RecognitionIssueType.invalidHandSize),
    );
    expect(tooManyCopies.canApply, isFalse);
    expect(tooManyHand.canApply, isFalse);
  });

  test('確認済み候補を既存局面へ一括置換する', () {
    final target = GameSituation()
      ..hand.add(Tile.red)
      ..ownRiver.add(Tile.white);
    final draft = builder.rebuild(
      imagePath: 'table.jpg',
      imageWidth: 1,
      imageHeight: 1,
      tiles: [
        _candidate('hand', Tile.m1, RecognitionRegion.ownHand, 0.9),
        _candidate('river', Tile.p2, RecognitionRegion.ownRiver, 0.9),
        _candidate('dora', Tile.s3, RecognitionRegion.doraIndicators, 0.9),
        for (var index = 0; index < 3; index++)
          _candidate(
            'meld-$index',
            Tile.east,
            RecognitionRegion.upperMelds,
            0.9,
          ),
      ],
      modelVersion: 'test-model',
    );

    final applied = const ApplyRecognitionDraftUseCase().call(
      draft: draft,
      target: target,
      handLimit: 13,
    );

    expect(applied, isTrue);
    expect(target.hand, [Tile.m1]);
    expect(target.ownRiver, [Tile.p2]);
    expect(target.doraIndicators, [Tile.s3]);
    expect(target.melds.single.tiles, [Tile.east, Tile.east, Tile.east]);
    expect(target.melds.single.ownerRiver, InputTarget.upperRiver);
  });

  test('手牌上限に合わない候補は元の局面を変更しない', () {
    final target = GameSituation()
      ..hand.add(Tile.red)
      ..ownRiver.add(Tile.white);
    final draft = builder.rebuild(
      imagePath: 'table.jpg',
      imageWidth: 1,
      imageHeight: 1,
      tiles: [
        _candidate('first', Tile.m1, RecognitionRegion.ownHand, 0.9),
        _candidate('second', Tile.m2, RecognitionRegion.ownHand, 0.9),
      ],
      modelVersion: 'test-model',
    );

    final applied = const ApplyRecognitionDraftUseCase().call(
      draft: draft,
      target: target,
      handLimit: 1,
    );

    expect(applied, isFalse);
    expect(target.hand, [Tile.red]);
    expect(target.ownRiver, [Tile.white]);
  });
}

/// テスト用の認識候補を生成します。
RecognizedTile _candidate(
  String id,
  Tile? tile,
  RecognitionRegion region,
  double confidence,
) => RecognizedTile(
  id: id,
  tile: tile,
  boundingBox: const NormalizedRect(
    left: 0.1,
    top: 0.1,
    width: 0.1,
    height: 0.1,
  ),
  confidence: confidence,
  region: region,
);

/// 指定IDの配置候補を返します。
RecognitionRegion _regionOf(RecognitionDraft draft, String id) =>
    draft.tiles.singleWhere((candidate) => candidate.id == id).region;
