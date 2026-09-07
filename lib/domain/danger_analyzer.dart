import 'danger_assessment.dart';
import 'game_situation.dart';
import 'opponent.dart';
import 'tile.dart';
import 'visible_risk_rules.dart';

/// 入力済みの見える情報から、相手別の危険度を判定します。
class DangerAnalyzer {
  /// 共通の見える牌ルールを使う分析器を生成します。
  const DangerAnalyzer({this.visibleRiskRules = const VisibleRiskRules()});

  /// 待ち推定とも共通利用する守備材料です。
  final VisibleRiskRules visibleRiskRules;

  /// 数牌の判定開始時に使う比較用スコアです。
  static const numberTileBaseScore = VisibleRiskRules.numberTileBaseScore;

  /// 字牌の判定開始時に使う比較用スコアです。
  static const honorTileBaseScore = VisibleRiskRules.honorTileBaseScore;

  /// 「安全」と「注意」の境界値です。
  static const safeMaxScore = VisibleRiskRules.safeMaxScore;

  /// 「注意」と「危険」の境界値です。
  static const cautionMaxScore = VisibleRiskRules.cautionMaxScore;

  /// 入力局面から、自分の手牌にある牌種ごとの評価を返します。
  List<DangerAssessment> analyze(GameSituation situation, Opponent opponent) {
    _validate(situation);
    final candidates = situation.hand.toSet().toList()
      ..sort((first, second) => first.index.compareTo(second.index));
    return [
      for (final tile in candidates)
        visibleRiskRules.assess(situation, opponent, tile),
    ];
  }

  /// 比較用スコアを利用者向けの3段階へ変換します。
  static DangerLevel levelForScore(int score) =>
      VisibleRiskRules.levelForScore(score);

  /// ドラ表示牌に対応するドラを返します。
  static Tile doraForIndicator(Tile indicator) =>
      VisibleRiskRules.doraForIndicator(indicator);

  /// 同種牌が4枚を超える不正局面を拒否します。
  void _validate(GameSituation situation) {
    for (final tile in Tile.values) {
      if (situation.count(tile) > 4) {
        throw const DangerAnalysisException('同じ牌が5枚以上あります。局面入力を修正してください。');
      }
    }
  }
}
