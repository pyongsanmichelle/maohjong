import 'game_situation.dart';
import 'meld.dart';
import 'match_setup_validation.dart';
import 'round_progress.dart';
import 'round_result.dart';
import 'round_action_history.dart';
import 'tile.dart';

export 'round_result.dart' show RoundEndReason, RoundResult, SeatPosition;

/// 鳴きの対象にできる直前の打牌です。
class DiscardEvent {
  /// 打牌者と牌を保持するイベントを生成します。
  const DiscardEvent(this.river, this.tile, {this.actionId});

  /// 打牌者に対応する河です。
  final InputTarget river;

  /// 打牌された牌です。
  final Tile tile;

  /// 公開アクション履歴内の打牌IDです。互換入力では null です。
  final int? actionId;
}

/// 対局開始前の条件と、開始後の河入力順を管理します。
class MatchInputFlow {
  /// 指定した局面を使う入力フローを生成します。
  MatchInputFlow(
    this.situation, {
    RoundProgress? progress,
    RoundActionHistory? actionHistory,
  }) : progress = progress ?? RoundProgress(),
       actionHistory = actionHistory ?? RoundActionHistory();

  /// 入力対象となる局面です。
  final GameSituation situation;

  /// 局、巡目、残りツモ回数の進行状態です。
  final RoundProgress progress;

  /// 役・待ち推定に使う局内の公開アクション履歴です。
  final RoundActionHistory actionHistory;

  /// 選択中の親です。
  SeatPosition dealer = SeatPosition.self;

  /// 河の連続入力を開始済みかどうかです。
  bool started = false;

  /// 次に入力する河です。
  InputTarget currentRiver = InputTarget.ownRiver;

  /// 鳴きの対象にできる直前の打牌です。
  DiscardEvent? lastDiscard;

  /// 直近で終了した局の結果です。
  RoundResult? lastRoundResult;

  /// 自分が打牌する前にツモ入力を必要としているかどうかです。
  bool _turnNeedsDraw = false;

  /// カン成立後に新しいドラ表示牌の入力を待っているかどうかです。
  bool _kanDoraPending = false;

  /// 打牌取り消し時に局進行も戻すための履歴です。
  final List<_FlowDiscardAction> _discardHistory = [];

  /// 選択中の親を考慮した自分の開始時手牌上限です。
  int get handLimit =>
      (dealer == SeatPosition.self ? 14 : 13) - _ownMeldCount * 3;

  /// 開始後に副露数を考慮して保持できる手牌上限です。
  int get activeHandLimit => 14 - _ownMeldCount * 3;

  /// 現在の自分の番で、ツモ入力が必要かどうかを返します。
  bool get ownDrawRequired =>
      started && currentRiver == InputTarget.ownRiver && _turnNeedsDraw;

  /// 自分の手牌から打牌できる状態かどうかを返します。
  bool get canOwnDiscard =>
      started &&
      currentRiver == InputTarget.ownRiver &&
      !_turnNeedsDraw &&
      !_kanDoraPending;

  /// カン成立後、嶺上牌より先にドラ表示牌を入力する必要があるかどうかです。
  bool get kanDoraPending => started && _kanDoraPending;

  /// 現在の開始前入力を検証した結果です。
  MatchSetupValidation get setupValidation => MatchSetupValidator.validate(
    situation: situation,
    dealer: dealer,
    matchFinished: progress.matchFinished,
  );

  /// 親・最初のドラ・手牌が揃い、開始可能かどうかを返します。
  bool get canStart => setupValidation.canStart;

  /// 手牌上限を超えない場合に親を変更します。
  bool selectDealer(SeatPosition value) {
    final limit = (value == SeatPosition.self ? 14 : 13) - _ownMeldCount * 3;
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
    _kanDoraPending = false;
    _turnNeedsDraw =
        currentRiver == InputTarget.ownRiver &&
        situation.hand.length < activeHandLimit;
    _discardHistory.clear();
    actionHistory.seedFromSituation(situation, turn: progress.turn);
    return true;
  }

  /// ツモまたはロンで現在局を終了し、次局入力へ進めます。
  bool completeWin({
    required RoundEndReason reason,
    required SeatPosition winner,
  }) {
    if (!started || reason == RoundEndReason.exhaustiveDraw) return false;
    final discard = lastDiscard;
    final loser = reason == RoundEndReason.ron && discard != null
        ? seatForRiver(discard.river)
        : null;
    if (reason == RoundEndReason.ron && (loser == null || loser == winner)) {
      return false;
    }
    lastRoundResult = RoundResult(
      reason: reason,
      roundWind: progress.roundWind,
      kyoku: progress.kyoku,
      winner: winner,
      loser: loser,
    );
    progress.advanceRound();
    _completeRound();
    return true;
  }

  /// 設定の修正に戻ります。入力済みの牌は保持します。
  void returnToSetup() {
    started = false;
    lastDiscard = null;
    _kanDoraPending = false;
    _turnNeedsDraw = false;
    _discardHistory.clear();
    actionHistory.clearForNextRound();
  }

  /// 外部入力で置き換えた現在局の局面を、対局中の進行状態へ再同期します。
  void reseedFromSituation() {
    lastDiscard = null;
    _kanDoraPending = false;
    _discardHistory.clear();
    _turnNeedsDraw =
        started &&
        currentRiver == InputTarget.ownRiver &&
        situation.hand.length < activeHandLimit;
    actionHistory.seedFromSituation(situation, turn: progress.turn);
  }

  /// 局面と進行履歴を破棄し、新しい半荘を東1局から準備します。
  void resetForNewMatch() {
    situation.clearForNextRound();
    progress.resetForNewMatch();
    actionHistory.clearForNextRound();
    dealer = SeatPosition.self;
    started = false;
    currentRiver = InputTarget.ownRiver;
    lastDiscard = null;
    lastRoundResult = null;
    _kanDoraPending = false;
    _turnNeedsDraw = false;
    _discardHistory.clear();
  }

  /// 打牌順に次の河へ進めます。
  void advanceRiver() {
    currentRiver = nextRiver(currentRiver);
    _turnNeedsDraw = true;
  }

  /// 打牌を記録して次打者へ進めます。次局へ進んだ場合は true です。
  bool recordDiscard(
    InputTarget river,
    Tile tile, {
    DiscardSource source = DiscardSource.unknown,
    bool declaresRiichi = false,
  }) {
    if (_kanDoraPending) return false;
    final progressBeforeDiscard = progress.snapshot();
    final neededDraw = _turnNeedsDraw;
    if (neededDraw && river != InputTarget.ownRiver) {
      progress.recordDraw();
    }
    final action = actionHistory.appendDiscard(
      actor: river,
      tile: tile,
      turn: progressBeforeDiscard.turn,
      source: source,
      declaresRiichi: declaresRiichi,
    );
    _discardHistory.add(
      _FlowDiscardAction(river, progressBeforeDiscard, neededDraw, action.id),
    );
    lastDiscard = DiscardEvent(river, tile, actionId: action.id);
    if (progress.recordDiscard()) {
      lastRoundResult = RoundResult(
        reason: RoundEndReason.exhaustiveDraw,
        roundWind: progressBeforeDiscard.roundWind,
        kyoku: progressBeforeDiscard.kyoku,
      );
      _completeRound();
      return true;
    }
    currentRiver = nextRiver(river);
    _turnNeedsDraw = true;
    return false;
  }

  /// 自分のツモ牌が入力されたことを記録します。
  bool markOwnDrawn() {
    if (!ownDrawRequired || _kanDoraPending) return false;
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
  bool acceptCall(MeldType type, InputTarget callerRiver, {Meld? meld}) {
    if (_kanDoraPending || !callersFor(type).contains(callerRiver)) {
      return false;
    }
    if (meld != null) {
      actionHistory.appendMeld(
        meld: meld,
        calledDiscardId: lastDiscard?.actionId,
      );
    }
    currentRiver = callerRiver;
    lastDiscard = null;
    _turnNeedsDraw = type == MeldType.kan;
    _kanDoraPending = type == MeldType.kan;
    return true;
  }

  /// 自分の番の暗槓・加槓を受け付け、嶺上牌の入力待ちにします。
  bool acceptSelfKan({Meld? meld}) {
    if (!canOwnDiscard || _kanDoraPending) return false;
    if (meld != null) actionHistory.appendMeld(meld: meld);
    lastDiscard = null;
    _turnNeedsDraw = true;
    _kanDoraPending = true;
    return true;
  }

  /// 局面補正で登録したカンについて、ドラ表示牌の入力待ちを開始します。
  bool requireKanDoraIndicator() {
    if (!started || _kanDoraPending) return false;
    _kanDoraPending = true;
    return true;
  }

  /// 新しいドラ表示牌の入力を確定し、嶺上牌入力へ進める状態にします。
  bool confirmKanDoraIndicator() {
    if (!kanDoraPending) return false;
    _kanDoraPending = false;
    return true;
  }

  /// 嶺上牌入力前の暗槓・加槓を取り消し、打牌可能へ戻します。
  bool cancelSelfKan({Meld? meld}) {
    if (!ownDrawRequired) return false;
    if (meld != null) actionHistory.removeMeld(meld);
    _turnNeedsDraw = false;
    _kanDoraPending = false;
    return true;
  }

  /// 副露の取り消し後、元の打牌を再び鳴き対象として復元します。
  void restoreCallOpportunity(InputTarget river, Tile tile, {Meld? meld}) {
    if (meld != null) actionHistory.removeMeld(meld);
    final discard = actionHistory.latestVisibleDiscard(river, tile);
    lastDiscard = DiscardEvent(river, tile, actionId: discard?.id);
    currentRiver = nextRiver(river);
    _turnNeedsDraw = true;
    _kanDoraPending = false;
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
        actionHistory.removeFrom(action.actionId);
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

  /// 河の入力先からプレイヤー位置を返します。
  static SeatPosition? seatForRiver(InputTarget river) => switch (river) {
    InputTarget.ownRiver => SeatPosition.self,
    InputTarget.lowerRiver => SeatPosition.lower,
    InputTarget.acrossRiver => SeatPosition.across,
    InputTarget.upperRiver => SeatPosition.upper,
    _ => null,
  };

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
    _kanDoraPending = false;
    _turnNeedsDraw = false;
    _discardHistory.clear();
    situation.clearForNextRound();
    actionHistory.clearForNextRound();
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

  /// 自分が公開または申告している副露・カンの数です。
  int get _ownMeldCount => situation.meldsFor(InputTarget.ownRiver).length;
}

/// 打牌取り消しに必要な局進行とツモ要否を保持します。
class _FlowDiscardAction {
  /// 打牌前の状態を生成します。
  const _FlowDiscardAction(
    this.river,
    this.progressBeforeDiscard,
    this.neededDraw,
    this.actionId,
  );

  final InputTarget river;
  final RoundProgressSnapshot progressBeforeDiscard;
  final bool neededDraw;
  final int actionId;
}
