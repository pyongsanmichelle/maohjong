import '../domain/game_situation.dart';
import '../domain/meld.dart';
import '../domain/situation_editor.dart';
import '../domain/tile.dart';
import '../domain/tile_recognition.dart';

/// 画像認識器が返す、まだ局面へ割り当てていない検出結果です。
class TileRecognitionResult {
  /// 認識結果を生成します。
  const TileRecognitionResult({
    required this.imageWidth,
    required this.imageHeight,
    required this.tiles,
    required this.modelVersion,
  });

  /// 認識対象画像の横ピクセル数です。
  final int imageWidth;

  /// 認識対象画像の縦ピクセル数です。
  final int imageHeight;

  /// 画像内で検出した牌です。
  final List<RecognizedTile> tiles;

  /// 使用したモデルの版です。
  final String modelVersion;
}

/// 静止画から牌の位置と種類を検出する差し替え可能な窓口です。
abstract interface class MahjongTileRecognizer {
  /// 端末内画像を認識し、局面へ未反映の候補を返します。
  Future<TileRecognitionResult> recognize(String imagePath);

  /// 認識器が保持するネイティブ資源を解放します。
  void dispose();
}

/// 検出結果を領域別の確認用下書きへ変換します。
class BuildRecognitionDraftUseCase {
  /// 位置に基づく配置と警告判定を行うUseCaseを生成します。
  const BuildRecognitionDraftUseCase({this.lowConfidenceThreshold = 0.45});

  /// 利用者確認を促す信頼度の基準です。
  final double lowConfidenceThreshold;

  /// 認識結果から編集可能な下書きを生成します。
  RecognitionDraft call({
    required String imagePath,
    required TileRecognitionResult result,
  }) {
    final assigned =
        result.tiles
            .map(
              (candidate) => candidate.region == RecognitionRegion.unknown
                  ? candidate.copyWith(
                      region: _regionFor(candidate.boundingBox),
                    )
                  : candidate,
            )
            .toList()
          ..sort(_readingOrder);
    return rebuild(
      imagePath: imagePath,
      imageWidth: result.imageWidth,
      imageHeight: result.imageHeight,
      tiles: assigned,
      modelVersion: result.modelVersion,
    );
  }

  /// 利用者が訂正した候補の警告と確定可否を再計算します。
  RecognitionDraft rebuild({
    required String imagePath,
    required int imageWidth,
    required int imageHeight,
    required List<RecognizedTile> tiles,
    required String modelVersion,
  }) {
    final issues = <RecognitionIssue>[];
    for (final candidate in tiles) {
      if (candidate.tile == null) {
        issues.add(
          RecognitionIssue(
            type: RecognitionIssueType.unknownTile,
            tileId: candidate.id,
          ),
        );
      }
      if (candidate.region == RecognitionRegion.unknown) {
        issues.add(
          RecognitionIssue(
            type: RecognitionIssueType.unknownRegion,
            tileId: candidate.id,
          ),
        );
      }
      if (!candidate.editedByUser &&
          candidate.confidence < lowConfidenceThreshold) {
        issues.add(
          RecognitionIssue(
            type: RecognitionIssueType.lowConfidence,
            tileId: candidate.id,
          ),
        );
      }
    }
    for (final tile in Tile.values) {
      final count = tiles.where((candidate) => candidate.tile == tile).length;
      if (count > SituationEditor.maxCopiesPerTile) {
        issues.add(
          RecognitionIssue(
            type: RecognitionIssueType.tooManyCopies,
            tile: tile,
          ),
        );
      }
    }
    if (tiles.where((tile) => tile.region == RecognitionRegion.ownHand).length >
        14) {
      issues.add(
        const RecognitionIssue(type: RecognitionIssueType.invalidHandSize),
      );
    }
    for (final region in _meldRegions) {
      if (!_canPartitionMelds(_tilesIn(tiles, region))) {
        issues.add(
          const RecognitionIssue(type: RecognitionIssueType.unsupportedMeld),
        );
      }
    }
    return RecognitionDraft(
      imagePath: imagePath,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      tiles: List.unmodifiable(tiles),
      issues: List.unmodifiable(issues),
      modelVersion: modelVersion,
    );
  }

  /// 卓上の概略位置から最初の配置候補を返します。
  RecognitionRegion _regionFor(NormalizedRect box) {
    final x = box.centerX;
    final y = box.centerY;
    if (x >= 0.43 && x <= 0.57 && y >= 0.43 && y <= 0.57) {
      return RecognitionRegion.doraIndicators;
    }
    if (y >= 0.78) return RecognitionRegion.ownHand;
    if (y >= 0.60 && x >= 0.25 && x <= 0.75) {
      return RecognitionRegion.ownRiver;
    }
    if (y <= 0.36 && x >= 0.24 && x <= 0.76) {
      return RecognitionRegion.acrossRiver;
    }
    if (x < 0.36 && y >= 0.22 && y <= 0.78) {
      return RecognitionRegion.upperRiver;
    }
    if (x > 0.64 && y >= 0.22 && y <= 0.78) {
      return RecognitionRegion.lowerRiver;
    }
    return RecognitionRegion.unknown;
  }

  /// 画面上で上から左へ読める安定した候補順を返します。
  int _readingOrder(RecognizedTile first, RecognizedTile second) {
    final region = first.region.index.compareTo(second.region.index);
    if (region != 0) return region;
    final row = first.boundingBox.centerY.compareTo(second.boundingBox.centerY);
    if (row.abs() > 0.04) return row;
    return first.boundingBox.centerX.compareTo(second.boundingBox.centerX);
  }
}

/// 確認済みの認識下書きを既存局面へ一括反映します。
class ApplyRecognitionDraftUseCase {
  /// 局面変換UseCaseを生成します。
  const ApplyRecognitionDraftUseCase();

  /// 正常時だけ対象局面を更新し、反映できたかどうかを返します。
  bool call({
    required RecognitionDraft draft,
    required GameSituation target,
    required int handLimit,
  }) {
    if (!draft.canApply) return false;
    final replacement = GameSituation();
    final editor = SituationEditor(replacement);
    for (final candidate in draft.tiles) {
      final tile = candidate.tile;
      if (tile == null) return false;
      final inputTarget = _inputTargetFor(candidate.region);
      if (inputTarget != null && !editor.add(inputTarget, tile)) return false;
    }
    final melds = <Meld>[];
    for (final region in _meldRegions) {
      final owner = _inputTargetForMeld(region);
      final tiles = _tilesIn(draft.tiles, region);
      final built = _partitionMelds(tiles, owner);
      if (built == null) return false;
      melds.addAll(built);
    }
    replacement.melds.addAll(melds);
    if (replacement.hand.length > handLimit) return false;
    for (final tile in Tile.values) {
      if (replacement.count(tile) > SituationEditor.maxCopiesPerTile) {
        return false;
      }
    }

    target
      ..clearForNextRound()
      ..hand.addAll(replacement.hand)
      ..ownRiver.addAll(replacement.ownRiver)
      ..upperRiver.addAll(replacement.upperRiver)
      ..acrossRiver.addAll(replacement.acrossRiver)
      ..lowerRiver.addAll(replacement.lowerRiver)
      ..doraIndicators.addAll(replacement.doraIndicators)
      ..melds.addAll(replacement.melds);
    return true;
  }
}

/// 通常の牌領域を既存入力先へ変換します。
InputTarget? _inputTargetFor(RecognitionRegion region) => switch (region) {
  RecognitionRegion.ownHand => InputTarget.hand,
  RecognitionRegion.ownRiver => InputTarget.ownRiver,
  RecognitionRegion.upperRiver => InputTarget.upperRiver,
  RecognitionRegion.acrossRiver => InputTarget.acrossRiver,
  RecognitionRegion.lowerRiver => InputTarget.lowerRiver,
  RecognitionRegion.doraIndicators => InputTarget.doraIndicators,
  _ => null,
};

/// 副露領域を所有者の河へ変換します。
InputTarget _inputTargetForMeld(RecognitionRegion region) => switch (region) {
  RecognitionRegion.ownMelds => InputTarget.ownRiver,
  RecognitionRegion.upperMelds => InputTarget.upperRiver,
  RecognitionRegion.acrossMelds => InputTarget.acrossRiver,
  RecognitionRegion.lowerMelds => InputTarget.lowerRiver,
  _ => throw ArgumentError.value(region, 'region'),
};

/// 副露として扱う認識領域です。
const _meldRegions = <RecognitionRegion>[
  RecognitionRegion.ownMelds,
  RecognitionRegion.upperMelds,
  RecognitionRegion.acrossMelds,
  RecognitionRegion.lowerMelds,
];

/// 指定領域の確定済み牌だけを候補順に返します。
List<Tile> _tilesIn(
  Iterable<RecognizedTile> candidates,
  RecognitionRegion region,
) => [
  for (final candidate in candidates)
    if (candidate.region == region && candidate.tile != null) candidate.tile!,
];

/// 牌一覧を有効な副露へ分割できるかを返します。
bool _canPartitionMelds(List<Tile> tiles) =>
    _partitionMelds(tiles, InputTarget.ownRiver) != null;

/// 並び順どおりの牌をチー・ポン・カンの組へ分割します。
List<Meld>? _partitionMelds(List<Tile> tiles, InputTarget owner) {
  if (tiles.isEmpty) return const [];
  final result = <Meld>[];
  var index = 0;
  while (index < tiles.length) {
    final remaining = tiles.length - index;
    if (remaining >= 4 &&
        tiles.sublist(index, index + 4).every((tile) => tile == tiles[index])) {
      final group = List<Tile>.unmodifiable(tiles.sublist(index, index + 4));
      result.add(
        Meld(
          type: MeldType.kan,
          ownerRiver: owner,
          tiles: group,
          calledTile: group.first,
          fromRiver: null,
          kanType: KanType.open,
          origin: MeldOrigin.setup,
        ),
      );
      index += 4;
      continue;
    }
    if (remaining < 3) return null;
    final group = List<Tile>.unmodifiable(tiles.sublist(index, index + 3));
    final isPon = group.every((tile) => tile == group.first);
    final sorted = List<Tile>.from(group)..sort((a, b) => a.index - b.index);
    final isChi = _isSequence(sorted);
    if (!isPon && !isChi) return null;
    result.add(
      Meld(
        type: isPon ? MeldType.pon : MeldType.chi,
        ownerRiver: owner,
        tiles: group,
        calledTile: group.first,
        fromRiver: null,
        origin: MeldOrigin.setup,
      ),
    );
    index += 3;
  }
  return result;
}

/// 3枚が同じ数牌の連続形かを返します。
bool _isSequence(List<Tile> tiles) {
  if (tiles.length != 3 || tiles.last.index >= Tile.east.index) return false;
  final suit = tiles.first.index ~/ 9;
  return tiles.every((tile) => tile.index ~/ 9 == suit) &&
      tiles[1].index == tiles[0].index + 1 &&
      tiles[2].index == tiles[1].index + 1;
}
