import 'game_situation.dart';
import 'meld.dart';
import 'tile.dart';

/// 打牌が手出しかツモ切りかを表します。
enum DiscardSource { unknown, drawn, fromHand }

/// 局内で観測した公開アクションの共通情報です。
sealed class RoundAction {
  /// 局内ID、発生順、行為者を持つアクションを生成します。
  const RoundAction({
    required this.id,
    required this.sequence,
    required this.actor,
  });

  /// 訂正や副露との関連付けに使う局内一意IDです。
  final int id;

  /// 発生順を表す単調増加の番号です。
  final int sequence;

  /// 行為者に対応する河です。
  final InputTarget actor;
}

/// 河へ捨てられた1枚と、その時点の公開メタデータです。
class DiscardAction extends RoundAction {
  /// 打牌アクションを生成します。
  const DiscardAction({
    required super.id,
    required super.sequence,
    required super.actor,
    required this.tile,
    required this.source,
    required this.declaresRiichi,
    required this.turn,
    required this.visibleInRiver,
  });

  /// 捨てられた牌です。
  final Tile tile;

  /// 手出し、ツモ切り、または不明です。
  final DiscardSource source;

  /// この打牌がリーチ宣言牌かどうかです。
  final bool declaresRiichi;

  /// 登録時点の巡目です。
  final int turn;

  /// 鳴かれず河に残っているかどうかです。
  final bool visibleInRiver;

  /// 指定された属性だけを置き換えた新しい打牌を返します。
  DiscardAction copyWith({
    DiscardSource? source,
    bool? declaresRiichi,
    bool? visibleInRiver,
  }) => DiscardAction(
    id: id,
    sequence: sequence,
    actor: actor,
    tile: tile,
    source: source ?? this.source,
    declaresRiichi: declaresRiichi ?? this.declaresRiichi,
    turn: turn,
    visibleInRiver: visibleInRiver ?? this.visibleInRiver,
  );
}

/// 公開副露と、鳴き元の打牌との時系列関係です。
class MeldAction extends RoundAction {
  /// 副露アクションを生成します。
  const MeldAction({
    required super.id,
    required super.sequence,
    required super.actor,
    required this.meld,
    required this.calledDiscardId,
    required this.declaredAfterSequence,
  });

  /// 既存の公開副露です。
  final Meld meld;

  /// 鳴き元の打牌IDです。開始時登録では null です。
  final int? calledDiscardId;

  /// 副露が発生した直前のアクション番号です。
  final int declaredAfterSequence;
}

/// 局内の公開アクションを発生順に保持し、訂正を一元管理します。
class RoundActionHistory {
  final List<RoundAction> _actions = [];
  int _nextId = 1;
  int _nextSequence = 1;

  /// 現在のアクションを変更不能な一覧として返します。
  List<RoundAction> get actions => List.unmodifiable(_actions);

  /// 次に採番される局内連番です。
  int get nextSequence => _nextSequence;

  /// 打牌を履歴末尾へ追加して返します。
  DiscardAction appendDiscard({
    required InputTarget actor,
    required Tile tile,
    required int turn,
    DiscardSource source = DiscardSource.unknown,
    bool declaresRiichi = false,
  }) {
    if (declaresRiichi) _clearRiichiForActor(actor);
    final action = DiscardAction(
      id: _nextId++,
      sequence: _nextSequence++,
      actor: actor,
      tile: tile,
      source: source,
      declaresRiichi: declaresRiichi,
      turn: turn,
      visibleInRiver: true,
    );
    _actions.add(action);
    return action;
  }

  /// 副露を履歴末尾へ追加し、鳴き元の打牌を河から非表示にします。
  MeldAction appendMeld({required Meld meld, int? calledDiscardId}) {
    if (calledDiscardId != null) {
      _replaceDiscard(calledDiscardId, visibleInRiver: false);
    }
    final action = MeldAction(
      id: _nextId++,
      sequence: _nextSequence++,
      actor: meld.ownerRiver,
      meld: meld,
      calledDiscardId: calledDiscardId,
      declaredAfterSequence: _nextSequence - 2,
    );
    _actions.add(action);
    return action;
  }

  /// 打牌の手出し区分またはリーチ属性を訂正します。
  bool updateDiscard(
    int id, {
    required DiscardSource source,
    required bool declaresRiichi,
  }) {
    final current = discardById(id);
    if (current == null) return false;
    if (declaresRiichi) _clearRiichiForActor(current.actor, exceptId: id);
    return _replaceDiscard(id, source: source, declaresRiichi: declaresRiichi);
  }

  /// 指定された副露を除き、鳴き元の打牌を河表示へ戻します。
  bool removeMeld(Meld meld) {
    final index = _actions.lastIndexWhere(
      (action) => action is MeldAction && identical(action.meld, meld),
    );
    if (index == -1) return false;
    final action = _actions.removeAt(index) as MeldAction;
    final discardId = action.calledDiscardId;
    if (discardId != null) _replaceDiscard(discardId, visibleInRiver: true);
    return true;
  }

  /// 指定したアクション以降を削除し、関連する打牌表示を復元します。
  bool removeFrom(int id) {
    final index = _actions.indexWhere((action) => action.id == id);
    if (index == -1) return false;
    final removed = _actions.sublist(index);
    _actions.removeRange(index, _actions.length);
    for (final action in removed.whereType<MeldAction>()) {
      final discardId = action.calledDiscardId;
      if (discardId != null) _replaceDiscard(discardId, visibleInRiver: true);
    }
    return true;
  }

  /// 次局に備えて履歴と採番を初期化します。
  void clearForNextRound() {
    _actions.clear();
    _nextId = 1;
    _nextSequence = 1;
  }

  /// 開始時点の河と副露を時系列不明の互換履歴として登録します。
  void seedFromSituation(GameSituation situation, {required int turn}) {
    clearForNextRound();
    for (final river in const [
      InputTarget.ownRiver,
      InputTarget.lowerRiver,
      InputTarget.acrossRiver,
      InputTarget.upperRiver,
    ]) {
      for (final tile in situation.tilesFor(river)) {
        appendDiscard(actor: river, tile: tile, turn: turn);
      }
    }
    for (final meld in situation.melds) {
      final sourceRiver = meld.fromRiver;
      final calledDiscard = sourceRiver == null
          ? null
          : appendDiscard(
              actor: sourceRiver,
              tile: meld.calledTile,
              turn: turn,
            );
      appendMeld(meld: meld, calledDiscardId: calledDiscard?.id);
    }
  }

  /// 指定IDの打牌を検索します。
  DiscardAction? discardById(int id) {
    for (final action in _actions.whereType<DiscardAction>()) {
      if (action.id == id) return action;
    }
    return null;
  }

  /// 指定河・牌に一致し、現在河に見えている最後の打牌を返します。
  DiscardAction? latestVisibleDiscard(InputTarget actor, Tile tile) {
    for (final action
        in _actions.whereType<DiscardAction>().toList().reversed) {
      if (action.actor == actor &&
          action.tile == tile &&
          action.visibleInRiver) {
        return action;
      }
    }
    return null;
  }

  /// 指定された打牌の属性を置き換えます。
  bool _replaceDiscard(
    int id, {
    DiscardSource? source,
    bool? declaresRiichi,
    bool? visibleInRiver,
  }) {
    final index = _actions.indexWhere(
      (action) => action is DiscardAction && action.id == id,
    );
    if (index == -1) return false;
    final current = _actions[index] as DiscardAction;
    _actions[index] = current.copyWith(
      source: source,
      declaresRiichi: declaresRiichi,
      visibleInRiver: visibleInRiver,
    );
    return true;
  }

  /// 同じ行為者の別打牌からリーチ属性を取り除きます。
  void _clearRiichiForActor(InputTarget actor, {int? exceptId}) {
    for (var index = 0; index < _actions.length; index++) {
      final action = _actions[index];
      if (action is DiscardAction &&
          action.actor == actor &&
          action.id != exceptId &&
          action.declaresRiichi) {
        _actions[index] = action.copyWith(declaresRiichi: false);
      }
    }
  }
}
