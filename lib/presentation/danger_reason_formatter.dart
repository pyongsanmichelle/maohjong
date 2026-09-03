import '../domain/danger_assessment.dart';
import 'tile_presentation.dart';

/// 判定理由の構造化データを日本語の説明文へ変換します。
class DangerReasonFormatter {
  /// 状態を持たない変換器を生成します。
  const DangerReasonFormatter();

  /// 利用者向けの短い説明文を返します。
  String format(DangerReason reason) => switch (reason.code) {
    DangerReasonCode.genbutsu => '対象相手の捨て牌に同じ牌がある現物です。',
    DangerReasonCode.allCopiesVisible => '同じ牌が局面全体で4枚見えています。',
    DangerReasonCode.fullSuji => '${_tiles(reason)}が捨てられており、両側の筋情報があります。',
    DangerReasonCode.suji => '${_tiles(reason)}が捨てられており、筋情報があります。',
    DangerReasonCode.kabe => '${_tiles(reason)}が4枚見えており、両面形の一部を否定できます。',
    DangerReasonCode.oneChance => '${_tiles(reason)}が3枚見えているワンチャンスです。',
    DangerReasonCode.dora =>
      'ドラ表示牌${_tiles(reason)}から求めたドラです（${reason.evidenceCount}枚分）。',
    DangerReasonCode.openSuitPressure =>
      '対象相手に同じ色の副露が${reason.evidenceCount}組あり、この色は注意が必要です。',
    DangerReasonCode.honorVisibility =>
      '同じ字牌が局面全体で${reason.evidenceCount}枚見えています。',
    DangerReasonCode.noStrongEvidence => '入力済み情報から強い安全材料が見つかりません。',
  };

  /// 根拠牌を読点で区切った表示名へ変換します。
  String _tiles(DangerReason reason) =>
      reason.relatedTiles.map(tileLabel).join('・');
}
