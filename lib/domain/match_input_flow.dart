import 'game_situation.dart';
import 'meld.dart';
import 'round_progress.dart';
import 'tile.dart';

/// 自分から見たプレイヤーの位置です。
enum SeatPosition { self, lower, across, upper }

/// 鳴きの対象にできる直前の打牌です。
class DiscardEvent {
  /// 打牌者と牌を保持するイベントを生成します。
  const DiscardEvent(this.river, this.tile);

  /// 打牌者に対応する河です。
  final InputTarget river;

  /// 打牌された牌です。
  final Tile tile;
}

/// 対局開始前の条件と、開始後の河入力順を管理します。
class MatchInputFlow {
  /// 指定した局面を使う入力フローを生成します。
  MatchInputFlow(this.situation, {RoundProgress? progress})
    : progress = progress ?? RoundProgress();

  /// 入力対象となる局面です。
  final GameSituation situation;

  /// 局、巡目、残りツモ回数の進行状態です。
  final RoundProgress progress;

  /// 選択中の親です。
  SeatPosition dealer = SeatPosition.self;

  /// 河の連続入力を開始済みかどうかです。
  bool started = false;

  /// 次に入力する河です。
  InputTarget currentRiver = InputTarget.ownRiver;

  /// 鳴きの対象にできる直前の打牌です。
  DiscardEvent? lastDiscard;

  /// 自分が打牌する前にツモ入力を必要としているかどうかです。
  bool _turnNeedsDraw = false;

  /// 打牌取り消し時に局進行も戻すための履歴です。
  final List<_FlowDiscardAction> _discardHistory = [];

  /// 選択中の親を考慮した自分の開始時手牌上限です。
  int get handLimit => dealer == SeatPosition.self ? 14 : 13;

  /// 現在の自分の番で、ツモ入力が必要かどうかを返します。
  bool get ownDrawRequired =>
      started && currentRiver == InputTarget.ownRiver && _turnNeedsDraw;

  /// 自分の手牌から打牌できる状態かどうかを返します。
  bool get canOwnDiscard =>
      started && currentRiver == InputTarget.ownRiver && !_turnNeedsDraw;

  /// 親・ドラ表示牌・手牌が揃い、開始可能かどうかを返します。
  bool get canStart =>
      !progress.matchFinished &&
      situation.doraIndicators.isNotEmpty &&
      situation.hand.isNotEmpty;

  /// 手牌上限を超えない場合に親を変更します。
  bool selectDealer(SeatPosition value) {
    final limit = value == SeatPosition.self ? 14 : 13;
    if (situation.hand.length > limit) return false;
    dealer = value;
    return true;
  }

  /// 親の河を先頭にして、河の連続入力を開始します。
  bool start() {
    if (!canStart) return false;
    started = true;
    currentRiver = _riverFor(dealer);
    lastDiscard = null;
    _turnNeedsDraw =
        currentRiver == InputTarget.ownRiver && situation.hand.length < 14;
    _discardHistory.clear();
    return true;
  }

  /// 設定の修正に戻ります。入力済みの牌は保持します。
  void returnToSetup() {
    started = false;
    lastDiscard = null;
    _turnNeedsDraw = false;
    _discardHistory.clear();
  }

  /// 打牌順に次の河へ進めます。
  void advanceRiver() {
    currentRiver = nextRiver(currentRiver);
    _turnNeedsDraw = true;
  }

  /// 打牌を記録して次打者へ進めます。次局へ進んだ場合は true です。
  bool recordDiscard(InputTarget river, Tile tile) {
    final progressBeforeDiscard = progress.snapshot();
    final neededDraw = _turnNeedsDraw;
    if (neededDraw && river != InputTarget.ownRiver) {
      progress.recordDraw();
    }
    _discardHistory.add(
      _FlowDiscardAction(river, progressBeforeDiscard, neededDraw),
    );
    lastDiscard = DiscardEvent(river, tile);
    if (progress.recordDiscard()) {
      _completeRound();
      return true;
    }
    currentRiver = nextRiver(river);
    _turnNeedsDraw = true;
    return false;
  }

  /// 自分のツモ牌が入力されたことを記録します。
  bool markOwnDrawn() {
    if (!ownDrawRequired) return false;
    if (!progress.recordDraw()) return false;
    _turnNeedsDraw = false;
    lastDiscard = null;
    return true;
  }

  /// ツモ入力を取り消し、自分の打牌を再び禁止します。
  void cancelOwnDraw() {
    if (started && currentRiver == InputTarget.ownRiver) {
      if (!_turnNeedsDraw) progress.restoreDraw();
      _turnNeedsDraw = true;
    }
  }

  /// 鳴いた人へ次の打牌入力先を変更します。
  bool acceptCall(MeldType type, InputTarget callerRiver) {
    if (!callersFor(type).contains(callerRiver)) return false;
    currentRiver = callerRiver;
    lastDiscard = null;
    _turnNeedsDraw = type == MeldType.kan;
    return true;
  }

  /// 副露の取り消し後、元の打牌を再び鳴き対象として復元します。
  void restoreCallOpportunity(InputTarget river, Tile tile) {
    lastDiscard = DiscardEvent(river, tile);
    currentRiver = nextRiver(river);
    _turnNeedsDraw = true;
  }

  /// 指定した鳴きで選べるプレイヤーの河を返します。
  List<InputTarget> callersFor(MeldType type) {
    final discard = lastDiscard;
    if (discard == null) return const [];
    if (type == MeldType.chi) return [nextRiver(discard.river)];
    return riverTargets.where((river) => river != discard.river).toList();
  }

  /// 指定牌を使って成立するチーの順子候補を返します。
  List<List<Tile>> chiSequences(Tile calledTile) {
    if (calledTile.index >= 27) return const [];
    final suitStart = (calledTile.index ~/ 9) * 9;
    final rank = calledTile.index % 9;
    final firstStart = rank - 2 < 0 ? 0 : rank - 2;
    final lastStart = rank > 6 ? 6 : rank;
    return [
      for (var start = firstStart; start <= lastStart; start++)
        [
          Tile.values[suitStart + start],
          Tile.values[suitStart + start + 1],
          Tile.values[suitStart + start + 2],
        ],
    ];
  }

  /// 指定した河の通常の次打者を返します。
  InputTarget nextRiver(InputTarget river) => switch (river) {
    InputTarget.ownRiver => InputTarget.lowerRiver,
    InputTarget.lowerRiver => InputTarget.acrossRiver,
    InputTarget.acrossRiver => InputTarget.upperRiver,
    InputTarget.upperRiver => InputTarget.ownRiver,
    _ => river,
  };

  /// 訂正対象の河へ入力位置を戻します。
  void rewindTo(InputTarget river) {
    if (_isRiver(river)) {
      currentRiver = river;
      lastDiscard = null;
      final action = _discardHistory.isNotEmpty ? _discardHistory.last : null;
      if (action != null && action.river == river) {
        progress.restore(action.progressBeforeDiscard);
        _turnNeedsDraw = action.neededDraw;
        _discardHistory.removeLast();
      } else {
        _turnNeedsDraw = false;
      }
    }
  }

  /// 河として利用できる4人分の入力先です。
  static const riverTargets = [
    InputTarget.ownRiver,
    InputTarget.lowerRiver,
    InputTarget.acrossRiver,
    InputTarget.upperRiver,
  ];

  /// 指定した位置に対応する河を返します。
  InputTarget _riverFor(SeatPosition seat) => switch (seat) {
    SeatPosition.self => InputTarget.ownRiver,
    SeatPosition.lower => InputTarget.lowerRiver,
    SeatPosition.across => InputTarget.acrossRiver,
    SeatPosition.upper => InputTarget.upperRiver,
  };

  /// 流局後に次局へ移り、局ごとの牌入力を初期化します。
  void _completeRound() {
    if (!progress.matchFinished) dealer = _nextSeat(dealer);
    started = false;
    currentRiver = _riverFor(dealer);
    lastDiscard = null;
    _turnNeedsDraw = false;
    _discardHistory.clear();
    situation.clearForNextRound();
  }

  /// 連荘なしの通常進行で次の親位置を返します。
  SeatPosition _nextSeat(SeatPosition seat) => switch (seat) {
    SeatPosition.self => SeatPosition.lower,
    SeatPosition.lower => SeatPosition.across,
    SeatPosition.across => SeatPosition.upper,
    SeatPosition.upper => SeatPosition.self,
  };

  /// 指定した入力先が河かどうかを返します。
  bool _isRiver(InputTarget target) => switch (target) {
    InputTarget.ownRiver ||
    InputTarget.lowerRiver ||
    InputTarget.acrossRiver ||
    InputTarget.upperRiver => true,
    _ => false,
  };
}

/// 打牌取り消しに必要な局進行とツモ要否を保持します。
class _FlowDiscardAction {
  /// 打牌前の状態を生成します。
  const _FlowDiscardAction(
    this.river,
    this.progressBeforeDiscard,
    this.neededDraw,
  );

  final InputTarget river;
  final RoundProgressSnapshot progressBeforeDiscard;
  final bool neededDraw;
}
