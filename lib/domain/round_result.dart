import 'round_progress.dart';

/// 自分から見たプレイヤーの位置です。
enum SeatPosition { self, lower, across, upper }

/// 局が終了した理由です。
enum RoundEndReason { tsumo, ron, exhaustiveDraw }

/// 直近局の終了理由と和了者を保持する構造化データです。
class RoundResult {
  /// 終了した場局と、和了または流局の内容を生成します。
  const RoundResult({
    required this.reason,
    required this.roundWind,
    required this.kyoku,
    this.winner,
    this.loser,
  });

  /// ツモ、ロン、流局の区別です。
  final RoundEndReason reason;

  /// 終了した局の場風です。
  final RoundWind roundWind;

  /// 終了した局番号です。
  final int kyoku;

  /// 和了者です。流局では null です。
  final SeatPosition? winner;

  /// ロンの放銃者です。ツモと流局では null です。
  final SeatPosition? loser;
}
