/// 局の場風を表します。
enum RoundWind { east, south }

/// 取り消し前へ局進行を戻すための不変スナップショットです。
class RoundProgressSnapshot {
  /// 現在の進行値を保持するスナップショットを生成します。
  const RoundProgressSnapshot({
    required this.roundWind,
    required this.kyoku,
    required this.turn,
    required this.remainingDraws,
    required this.discardsInTurn,
    required this.matchFinished,
  });

  final RoundWind roundWind;
  final int kyoku;
  final int turn;
  final int remainingDraws;
  final int discardsInTurn;
  final bool matchFinished;
}

/// 局、巡目、通常の山からツモできる残り回数を管理します。
class RoundProgress {
  /// 指定した局と巡目の進行状態を生成します。
  RoundProgress({
    this.roundWind = RoundWind.east,
    this.kyoku = 1,
    this.turn = 1,
  }) : remainingDraws = _estimatedDrawsForTurn(turn);

  /// 配牌後に通常の山からツモできる初期回数です。
  static const initialDraws = 69;

  /// 現在の場風です。
  RoundWind roundWind;

  /// 現在の局番号です。
  int kyoku;

  /// 現在の巡目です。
  int turn;

  /// 通常の山からツモできる残り回数です。
  int remainingDraws;

  /// 現在の巡目で入力済みの打牌人数です。
  int _discardsInTurn = 0;

  /// 半荘の南4局まで終了したかどうかです。
  bool matchFinished = false;

  /// 開始前に場風を選択し、終了状態を解除します。
  void selectRoundWind(RoundWind value) {
    roundWind = value;
    remainingDraws = _estimatedDrawsForTurn(turn);
    _discardsInTurn = 0;
    matchFinished = false;
  }

  /// 開始前に局番号を選択し、終了状態を解除します。
  void selectKyoku(int value) {
    kyoku = value.clamp(1, 4).toInt();
    remainingDraws = _estimatedDrawsForTurn(turn);
    _discardsInTurn = 0;
    matchFinished = false;
  }

  /// 開始前に巡目を選択し、残りツモ回数を概算し直します。
  void selectTurn(int value) {
    turn = value.clamp(1, 18).toInt();
    remainingDraws = _estimatedDrawsForTurn(turn);
    _discardsInTurn = 0;
    matchFinished = false;
  }

  /// 通常ツモまたは嶺上牌で山が1回分減ったことを記録します。
  bool recordDraw() {
    if (remainingDraws <= 0) return false;
    remainingDraws--;
    return true;
  }

  /// 取り消されたツモ1回分を通常の山へ戻します。
  void restoreDraw() {
    if (remainingDraws < initialDraws) remainingDraws++;
  }

  /// 現在の進行状態を取り消し用に保存します。
  RoundProgressSnapshot snapshot() => RoundProgressSnapshot(
    roundWind: roundWind,
    kyoku: kyoku,
    turn: turn,
    remainingDraws: remainingDraws,
    discardsInTurn: _discardsInTurn,
    matchFinished: matchFinished,
  );

  /// 保存した進行状態へ戻します。
  void restore(RoundProgressSnapshot snapshot) {
    roundWind = snapshot.roundWind;
    kyoku = snapshot.kyoku;
    turn = snapshot.turn;
    remainingDraws = snapshot.remainingDraws;
    _discardsInTurn = snapshot.discardsInTurn;
    matchFinished = snapshot.matchFinished;
  }

  /// 打牌を記録し、4人分で巡目を進めます。次局へ進んだ場合は true です。
  bool recordDiscard() {
    _discardsInTurn++;
    if (_discardsInTurn >= 4) {
      _discardsInTurn = 0;
      if (turn < 18) turn++;
    }
    if (remainingDraws > 0) return false;
    return advanceRound();
  }

  /// 次局へ進め、南4局終了時は半荘終了として保持します。
  bool advanceRound() {
    if (kyoku < 4) {
      kyoku++;
    } else if (roundWind == RoundWind.east) {
      roundWind = RoundWind.south;
      kyoku = 1;
    } else {
      matchFinished = true;
      return true;
    }
    turn = 1;
    remainingDraws = initialDraws;
    _discardsInTurn = 0;
    return true;
  }

  /// 指定巡目を開始するときの残りツモ回数を概算します。
  static int _estimatedDrawsForTurn(int turn) {
    final estimate = initialDraws - (turn - 1) * 4;
    return estimate < 0 ? 0 : estimate;
  }
}
