import 'tile.dart';

/// 自分から見た守備分析対象の相手です。
enum Opponent { upper, across, lower }

/// 守備分析対象と既存の河入力先を対応付けます。
extension OpponentRiver on Opponent {
  /// この相手に対応する河を返します。
  InputTarget get river => switch (this) {
    Opponent.upper => InputTarget.upperRiver,
    Opponent.across => InputTarget.acrossRiver,
    Opponent.lower => InputTarget.lowerRiver,
  };
}
