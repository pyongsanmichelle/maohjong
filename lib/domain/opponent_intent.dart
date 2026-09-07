import 'opponent.dart';
import 'opponent_analysis_context.dart';
import 'tile.dart';

/// 初期版で推定する役の種類です。
enum YakuKind {
  honitsu,
  chinitsu,
  toitoi,
  yakuhai,
  tanyao,
  chanta,
  junchan,
  ittsuu,
  sanshokuDoujun,
  chiitoitsu,
  kokushiMusou,
}

/// 相対確信度スコアに対応する表示段階です。
enum IntentConfidenceLevel {
  weak,
  candidate,
  likely,
  confirmedByOpenInformation,
}

/// 役候補の肯定根拠または反証を識別するコードです。
enum IntentReasonCode {
  sameSuitMelds,
  offSuitDiscards,
  honorsRetainedPattern,
  tripletMelds,
  sequenceMelds,
  yakuhaiMeld,
  allSimpleMelds,
  terminalHonorMelds,
  straightComponents,
  threeColorComponents,
  closedHandRequired,
  contradictingMeld,
  contradictingDiscardPattern,
  insufficientHiddenInformation,
}

/// 根拠が観測されたアクション番号の範囲です。
class EvidenceSequenceRange {
  /// 最初と最後のアクション番号を保持します。
  const EvidenceSequenceRange(this.first, this.last);

  /// 最初のアクション番号です。
  final int first;

  /// 最後のアクション番号です。
  final int last;
}

/// 役候補のスコアへ寄与した構造化根拠です。
class IntentReason {
  /// 理由コードと根拠値を生成します。
  IntentReason({
    required this.code,
    required this.scoreDelta,
    required this.priority,
    List<Tile> relatedTiles = const [],
    this.evidenceCount,
    this.sequenceRange,
  }) : relatedTiles = List.unmodifiable(relatedTiles);

  /// 理由の種類です。
  final IntentReasonCode code;

  /// 比較用スコアへの寄与値です。
  final int scoreDelta;

  /// 表示順です。小さい値を先に表示します。
  final int priority;

  /// 理由に関係する牌です。
  final List<Tile> relatedTiles;

  /// 副露数や打牌数などの補足値です。
  final int? evidenceCount;

  /// 時系列根拠が観測された範囲です。
  final EvidenceSequenceRange? sequenceRange;
}

/// 公開情報から得た相手別の役候補です。
class YakuHypothesis {
  /// 役、スコア、根拠と反証を保持する候補を生成します。
  YakuHypothesis({
    required this.yaku,
    required this.opponent,
    required this.score,
    required this.level,
    required List<IntentReason> positiveReasons,
    required List<IntentReason> negativeReasons,
    List<Tile> relatedTiles = const [],
  }) : positiveReasons = List.unmodifiable(positiveReasons),
       negativeReasons = List.unmodifiable(negativeReasons),
       relatedTiles = List.unmodifiable(relatedTiles);

  /// 推定対象の役です。
  final YakuKind yaku;

  /// 推定対象の相手です。
  final Opponent opponent;

  /// 0から100の相対確信度です。
  final int score;

  /// スコアに対応する表示段階です。
  final IntentConfidenceLevel level;

  /// スコアを上げた根拠です。
  final List<IntentReason> positiveReasons;

  /// スコアを下げた反証です。
  final List<IntentReason> negativeReasons;

  /// 役牌など役固有の牌です。
  final List<Tile> relatedTiles;
}

/// 待ち形として矛盾しない可能性の種類です。
enum WaitShape { ryanmen, kanchan, penchan, shanpon, tanki, unknown }

/// 待ち候補の評価理由を識別するコードです。
enum WaitReasonCode {
  dangerAssessment,
  yakuAlignment,
  meldNeighborhood,
  riichiDiscardNeighborhood,
  remainingCopies,
  furitenRisk,
  allCopiesVisible,
  weakEvidence,
}

/// 待ち候補の比較用スコアへ寄与した理由です。
class WaitReason {
  /// 理由コードと根拠値を生成します。
  WaitReason({
    required this.code,
    required this.scoreDelta,
    required this.priority,
    List<Tile> relatedTiles = const [],
    this.evidenceCount,
  }) : relatedTiles = List.unmodifiable(relatedTiles);

  /// 理由の種類です。
  final WaitReasonCode code;

  /// 比較用スコアへの寄与値です。
  final int scoreDelta;

  /// 表示順です。小さい値を先に表示します。
  final int priority;

  /// 理由に関係する牌です。
  final List<Tile> relatedTiles;

  /// 見込み残数などの補足値です。
  final int? evidenceCount;
}

/// 公開情報と矛盾しない相手別の待ち牌候補です。
class WaitCandidate {
  /// 牌、スコア、形、根拠を保持する候補を生成します。
  WaitCandidate({
    required this.tile,
    required this.opponent,
    required this.score,
    required this.remainingCopies,
    required List<WaitShape> possibleShapes,
    required List<WaitReason> reasons,
    required this.furitenRisk,
  }) : possibleShapes = List.unmodifiable(possibleShapes),
       reasons = List.unmodifiable(reasons);

  /// 待ち牌の候補です。
  final Tile tile;

  /// 推定対象の相手です。
  final Opponent opponent;

  /// 0から100の相対確信度です。
  final int score;

  /// 現在見えていない見込み枚数です。
  final int remainingCopies;

  /// 公開情報と矛盾しない待ち形候補です。
  final List<WaitShape> possibleShapes;

  /// スコアの構造化根拠です。
  final List<WaitReason> reasons;

  /// 同じ牌が河にありロンできない可能性があるかどうかです。
  final bool furitenRisk;
}

/// 画面へ返す相手分析全体の結果です。
class OpponentIntentAnalysis {
  /// 情報充足度、役候補、待ち候補、警告をまとめます。
  OpponentIntentAnalysis({
    required this.opponent,
    required this.evidenceSufficiency,
    required List<YakuHypothesis> yakuHypotheses,
    required List<WaitCandidate> waitCandidates,
    required List<OpponentAnalysisWarning> warnings,
  }) : yakuHypotheses = List.unmodifiable(yakuHypotheses),
       waitCandidates = List.unmodifiable(waitCandidates),
       warnings = List.unmodifiable(warnings);

  /// 分析対象の相手です。
  final Opponent opponent;

  /// 公開情報の充足度です。
  final EvidenceSufficiency evidenceSufficiency;

  /// 表示対象の役候補です。
  final List<YakuHypothesis> yakuHypotheses;

  /// 表示対象の待ち牌候補です。
  final List<WaitCandidate> waitCandidates;

  /// 入力上の注意コードです。
  final List<OpponentAnalysisWarning> warnings;
}

/// 相対確信度を表示段階へ変換します。
IntentConfidenceLevel intentLevelForScore(int score) {
  if (score >= 90) return IntentConfidenceLevel.confirmedByOpenInformation;
  if (score >= 65) return IntentConfidenceLevel.likely;
  if (score >= 45) return IntentConfidenceLevel.candidate;
  return IntentConfidenceLevel.weak;
}
