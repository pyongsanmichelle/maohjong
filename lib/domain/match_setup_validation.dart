import 'game_situation.dart';
import 'round_result.dart';
import 'tile.dart';

/// 対局開始前の入力で不足または不正な状態を表します。
enum SetupValidationIssue {
  handEmpty,
  doraMissing,
  tooManyInitialDora,
  handLimitExceeded,
  matchFinished,
  invalidVisibleTileCount,
}

/// 対局開始可否と、その理由コードをまとめた不変の検証結果です。
class MatchSetupValidation {
  /// 検出した問題を保持する検証結果を生成します。
  MatchSetupValidation(Iterable<SetupValidationIssue> issues)
    : issues = List.unmodifiable(issues);

  /// 開始を妨げている問題です。
  final List<SetupValidationIssue> issues;

  /// 現在の入力で対局を開始できるかどうかです。
  bool get canStart => issues.isEmpty;
}

/// 開始前の局面をUIに依存せず検証します。
class MatchSetupValidator {
  /// インスタンス化を禁止します。
  const MatchSetupValidator._();

  /// 手牌、最初のドラ、親、見えている牌数から開始可否を返します。
  static MatchSetupValidation validate({
    required GameSituation situation,
    required SeatPosition dealer,
    required bool matchFinished,
  }) {
    final issues = <SetupValidationIssue>[];
    if (matchFinished) issues.add(SetupValidationIssue.matchFinished);
    if (situation.hand.isEmpty) issues.add(SetupValidationIssue.handEmpty);
    if (situation.doraIndicators.isEmpty) {
      issues.add(SetupValidationIssue.doraMissing);
    } else if (situation.doraIndicators.length > 1) {
      issues.add(SetupValidationIssue.tooManyInitialDora);
    }
    final ownMeldCount = situation.meldsFor(InputTarget.ownRiver).length;
    final handLimit =
        (dealer == SeatPosition.self ? 14 : 13) - ownMeldCount * 3;
    if (situation.hand.length > handLimit) {
      issues.add(SetupValidationIssue.handLimitExceeded);
    }
    if (Tile.values.any((tile) => situation.count(tile) > 4)) {
      issues.add(SetupValidationIssue.invalidVisibleTileCount);
    }
    return MatchSetupValidation(issues);
  }
}
