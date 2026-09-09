import 'tile.dart';

/// 画像全体に対する0から1の比率で検出位置を表します。
class NormalizedRect {
  /// 正規化した矩形を生成します。
  const NormalizedRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  /// 左端の位置です。
  final double left;

  /// 上端の位置です。
  final double top;

  /// 矩形の幅です。
  final double width;

  /// 矩形の高さです。
  final double height;

  /// 矩形中央の横位置です。
  double get centerX => left + width / 2;

  /// 矩形中央の縦位置です。
  double get centerY => top + height / 2;

  /// 表示や変換で安全に使える範囲へ値を収めます。
  NormalizedRect clamped() {
    final safeLeft = left.clamp(0.0, 1.0).toDouble();
    final safeTop = top.clamp(0.0, 1.0).toDouble();
    return NormalizedRect(
      left: safeLeft,
      top: safeTop,
      width: width.clamp(0.0, 1.0 - safeLeft).toDouble(),
      height: height.clamp(0.0, 1.0 - safeTop).toDouble(),
    );
  }
}

/// 静止画から認識した牌の配置候補です。
enum RecognitionRegion {
  ownHand,
  ownRiver,
  upperRiver,
  acrossRiver,
  lowerRiver,
  ownMelds,
  upperMelds,
  acrossMelds,
  lowerMelds,
  doraIndicators,
  unknown,
}

/// 認識候補がモデル由来か利用者追加かを表します。
enum RecognitionSource { model, user }

/// 認識候補に対して確認が必要な理由です。
enum RecognitionIssueType {
  unknownTile,
  lowConfidence,
  unknownRegion,
  tooManyCopies,
  invalidHandSize,
  unsupportedMeld,
}

/// 画像上の1枚の牌に対する認識結果です。
class RecognizedTile {
  /// 牌の認識結果を生成します。
  const RecognizedTile({
    required this.id,
    required this.tile,
    required this.boundingBox,
    required this.confidence,
    required this.region,
    this.source = RecognitionSource.model,
    this.editedByUser = false,
  });

  /// 確認画面内で候補を識別するIDです。
  final String id;

  /// 最上位の牌種候補です。分類不能の場合はnullです。
  final Tile? tile;

  /// 元画像内の検出位置です。
  final NormalizedRect boundingBox;

  /// モデルが返した信頼度です。正答確率とは限りません。
  final double confidence;

  /// 卓上の配置候補です。
  final RecognitionRegion region;

  /// 候補を生成した入力元です。
  final RecognitionSource source;

  /// 利用者が牌種または配置を訂正したかどうかです。
  final bool editedByUser;

  /// 一部の値を変更した新しい候補を返します。
  RecognizedTile copyWith({
    Tile? tile,
    bool clearTile = false,
    RecognitionRegion? region,
    bool? editedByUser,
  }) => RecognizedTile(
    id: id,
    tile: clearTile ? null : tile ?? this.tile,
    boundingBox: boundingBox,
    confidence: confidence,
    region: region ?? this.region,
    source: source,
    editedByUser: editedByUser ?? this.editedByUser,
  );
}

/// 認識候補に含まれる警告または確定不能理由です。
class RecognitionIssue {
  /// 確認理由を生成します。
  const RecognitionIssue({required this.type, this.tileId, this.tile});

  /// 理由の種類です。
  final RecognitionIssueType type;

  /// 特定候補に紐づく場合のIDです。
  final String? tileId;

  /// 同一牌の枚数問題に紐づく場合の牌種です。
  final Tile? tile;

  /// 解消するまで局面へ反映できない理由かどうかです。
  bool get blocksApply => switch (type) {
    RecognitionIssueType.lowConfidence => false,
    _ => true,
  };
}

/// 利用者が確認する前の静止画認識結果です。
class RecognitionDraft {
  /// 認識候補と確認理由をまとめます。
  const RecognitionDraft({
    required this.imagePath,
    required this.imageWidth,
    required this.imageHeight,
    required this.tiles,
    required this.issues,
    required this.modelVersion,
  });

  /// 確認画面に表示する端末内の一時画像パスです。
  final String imagePath;

  /// 元画像の横ピクセル数です。
  final int imageWidth;

  /// 元画像の縦ピクセル数です。
  final int imageHeight;

  /// 検出・訂正された牌候補です。
  final List<RecognizedTile> tiles;

  /// 現在の候補に対する確認理由です。
  final List<RecognitionIssue> issues;

  /// 認識に利用したモデルの版です。
  final String modelVersion;

  /// 局面へ反映できる状態かどうかです。
  bool get canApply => issues.every((issue) => !issue.blocksApply);
}
