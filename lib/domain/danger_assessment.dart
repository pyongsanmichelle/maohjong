import 'opponent.dart';
import 'tile.dart';

/// 利用者へ表示する危険度の3段階区分です。
enum DangerLevel { safe, caution, danger }

/// 危険度が上下した理由を機械的に識別するコードです。
enum DangerReasonCode {
  genbutsu,
  allCopiesVisible,
  fullSuji,
  suji,
  kabe,
  oneChance,
  dora,
  openSuitPressure,
  honorVisibility,
  noStrongEvidence,
}

/// 危険度判定に使った理由と根拠値です。
class DangerReason {
  /// 理由を生成します。
  DangerReason({
    required this.code,
    required this.scoreDelta,
    required this.priority,
    List<Tile> relatedTiles = const [],
    this.evidenceCount,
  }) : relatedTiles = List.unmodifiable(relatedTiles);

  /// 理由の種類です。
  final DangerReasonCode code;

  /// 比較用スコアへ加算した値です。
  final int scoreDelta;

  /// 理由一覧内の表示優先度です。小さい値を先に表示します。
  final int priority;

  /// 筋、壁、ドラなどの根拠になった牌です。
  final List<Tile> relatedTiles;

  /// 見えている枚数やドラの重複数などの補足値です。
  final int? evidenceCount;
}

/// 1種類の牌について相手別に算出した守備評価です。
class DangerAssessment {
  /// 守備評価を生成します。
  DangerAssessment({
    required this.tile,
    required this.opponent,
    required this.score,
    required this.level,
    required List<DangerReason> reasons,
  }) : reasons = List.unmodifiable(reasons);

  /// 評価対象の牌です。
  final Tile tile;

  /// 評価対象の相手です。
  final Opponent opponent;

  /// 0から100までの相対比較用スコアです。
  final int score;

  /// 利用者へ表示する3段階の危険度です。
  final DangerLevel level;

  /// スコアの根拠です。
  final List<DangerReason> reasons;
}

/// 局面が守備分析できない理由を表します。
class DangerAnalysisException implements Exception {
  /// 表示可能な理由を保持する例外を生成します。
  const DangerAnalysisException(this.message);

  /// 利用者へ提示できるエラー内容です。
  final String message;

  @override
  String toString() => message;
}
