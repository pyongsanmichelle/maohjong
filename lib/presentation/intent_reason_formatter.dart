import '../domain/opponent_analysis_context.dart';
import '../domain/opponent_intent.dart';
import 'tile_presentation.dart';

/// 相手分析の構造化コードを日本語表示へ変換します。
class IntentReasonFormatter {
  /// 状態を持たないフォーマッターを生成します。
  const IntentReasonFormatter();

  /// 役の種類を表示名へ変換します。
  String yakuLabel(YakuKind yaku) => switch (yaku) {
    YakuKind.honitsu => '混一色',
    YakuKind.chinitsu => '清一色',
    YakuKind.toitoi => '対々和',
    YakuKind.yakuhai => '役牌',
    YakuKind.tanyao => '断么九',
    YakuKind.chanta => '混全帯么九',
    YakuKind.junchan => '純全帯么九',
    YakuKind.ittsuu => '一気通貫',
    YakuKind.sanshokuDoujun => '三色同順',
    YakuKind.chiitoitsu => '七対子',
    YakuKind.kokushiMusou => '国士無双',
  };

  /// 確信度段階を誤認しにくい表示名へ変換します。
  String confidenceLabel(IntentConfidenceLevel level) => switch (level) {
    IntentConfidenceLevel.weak => '弱い候補',
    IntentConfidenceLevel.candidate => '候補',
    IntentConfidenceLevel.likely => '有力',
    IntentConfidenceLevel.confirmedByOpenInformation => '公開情報から成立確認',
  };

  /// 役候補の理由を根拠値付きの文へ変換します。
  String formatIntentReason(IntentReason reason) {
    final count = reason.evidenceCount;
    final tiles = reason.relatedTiles.map(tileLabel).join('・');
    final detail = switch (reason.code) {
      IntentReasonCode.sameSuitMelds => '同じ色を中心とした副露が${count ?? 0}組あります',
      IntentReasonCode.offSuitDiscards => '対象外の色を${count ?? 0}枚捨てています',
      IntentReasonCode.honorsRetainedPattern => '字牌を保持している傾向があります',
      IntentReasonCode.tripletMelds => '刻子・槓子の副露が${count ?? 0}組あります',
      IntentReasonCode.sequenceMelds => '順子の副露が${count ?? 0}組あります',
      IntentReasonCode.yakuhaiMeld => '$tilesの刻子・槓子が公開されています',
      IntentReasonCode.allSimpleMelds => '中張牌だけの副露が${count ?? 0}組あります',
      IntentReasonCode.terminalHonorMelds => '么九牌を含む副露が${count ?? 0}組あります',
      IntentReasonCode.straightComponents => '一気通貫の公開順子が${count ?? 0}組あります',
      IntentReasonCode.threeColorComponents => '同じ並びの公開順子が${count ?? 0}色あります',
      IntentReasonCode.closedHandRequired => '副露があり門前条件を満たしません',
      IntentReasonCode.contradictingMeld => '役条件と異なる副露が${count ?? 0}組あります',
      IntentReasonCode.contradictingDiscardPattern => '河の傾向を弱い補助根拠として使っています',
      IntentReasonCode.insufficientHiddenInformation =>
        '非公開情報が多いため弱い候補に制限しています',
    };
    final sign = reason.scoreDelta > 0 ? '+' : '';
    return '$detail（$sign${reason.scoreDelta}）';
  }

  /// 待ち候補の理由を根拠値付きの文へ変換します。
  String formatWaitReason(WaitReason reason) {
    final count = reason.evidenceCount;
    final detail = switch (reason.code) {
      WaitReasonCode.dangerAssessment => '既存の守備材料による相対危険度 ${count ?? 0}',
      WaitReasonCode.yakuAlignment => '上位の役候補と牌種が整合します',
      WaitReasonCode.meldNeighborhood => '公開副露の形に近い牌です',
      WaitReasonCode.riichiDiscardNeighborhood => 'リーチ宣言牌前後の弱い補助根拠です',
      WaitReasonCode.remainingCopies => '見込み残数は${count ?? 0}枚です',
      WaitReasonCode.furitenRisk => '同じ牌が河にありロンできない可能性があります',
      WaitReasonCode.allCopiesVisible => '4枚すべて見えています',
      WaitReasonCode.weakEvidence => '候補を絞る情報が少ない状態です',
    };
    final sign = reason.scoreDelta > 0 ? '+' : '';
    return '$detail（$sign${reason.scoreDelta}）';
  }

  /// 待ち形を表示名へ変換します。
  String waitShapeLabel(WaitShape shape) => switch (shape) {
    WaitShape.ryanmen => '両面',
    WaitShape.kanchan => '嵌張',
    WaitShape.penchan => '辺張',
    WaitShape.shanpon => '双碰',
    WaitShape.tanki => '単騎',
    WaitShape.unknown => '不明',
  };

  /// 情報充足度に応じた空状態の案内を返します。
  String emptyMessage(EvidenceSufficiency sufficiency) => switch (sufficiency) {
    EvidenceSufficiency.none => '河・副露・リーチ情報を入力してください',
    EvidenceSufficiency.low => '待ちを絞る情報が不足しています',
    EvidenceSufficiency.usable => '表示基準に届く候補がありません',
  };
}
