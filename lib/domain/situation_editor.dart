import 'game_situation.dart';
import 'meld.dart';
import 'tile.dart';

/// 局面入力の追加、削除、取り消しと枚数制約を管理します。
class SituationEditor {
  /// 指定した局面を編集するエディタを生成します。
  SituationEditor(this.situation);

  /// 編集対象の局面です。
  final GameSituation situation;
  final List<_InputAction> _history = [];

  /// 同種牌を局面全体で保持できる上限です。
  static const maxCopiesPerTile = 4;

  /// 見えている牌を差し引いた、指定牌の未確認枚数を返します。
  int remainingCopies(Tile tile) => maxCopiesPerTile - situation.count(tile);

  /// 牌を編集先へ追加します。追加できない場合は false を返します。
  bool add(InputTarget target, Tile tile) {
    if (situation.count(tile) >= maxCopiesPerTile) return false;
    situation.tilesFor(target).add(tile);
    if (target == InputTarget.hand) _sortHand();
    _history.add(_InputAction.addition(target, tile));
    return true;
  }

  /// 手牌の牌を自分の河へ移します。移動できない場合は false を返します。
  bool discardFromHand(int index) {
    if (index < 0 || index >= situation.hand.length) return false;
    final tile = situation.hand.removeAt(index);
    situation.ownRiver.add(tile);
    _history.add(_InputAction.discard(tile, index));
    return true;
  }

  /// 直前の河牌を使う副露を確定し、公開牌の置き場所へ移します。
  Meld? declareMeld({
    required MeldType type,
    required InputTarget callerRiver,
    required InputTarget fromRiver,
    required Tile calledTile,
    required List<Tile> tiles,
  }) {
    if (!_isValidMeld(type, calledTile, tiles)) return null;
    final source = situation.tilesFor(fromRiver);
    final calledIndex = source.lastIndexOf(calledTile);
    if (calledIndex == -1) return null;

    final concealedTiles = List<Tile>.from(tiles)..remove(calledTile);
    final handIndices = callerRiver == InputTarget.ownRiver
        ? _matchingHandIndices(concealedTiles)
        : <int>[];
    if (callerRiver == InputTarget.ownRiver &&
        handIndices.length != concealedTiles.length) {
      return null;
    }
    if (callerRiver != InputTarget.ownRiver &&
        !_canExposeOpponentMeld(calledTile, tiles)) {
      return null;
    }

    source.removeAt(calledIndex);
    for (final index in handIndices.reversed) {
      situation.hand.removeAt(index);
    }
    final meld = Meld(
      type: type,
      ownerRiver: callerRiver,
      tiles: List.unmodifiable(tiles),
      calledTile: calledTile,
      fromRiver: fromRiver,
    );
    situation.melds.add(meld);
    clearHistory();
    return meld;
  }

  /// 副露を取り消し、鳴かれた牌と自分の使用牌を元へ戻します。
  bool removeMeld(Meld meld) {
    if (!situation.melds.remove(meld)) return false;
    situation.tilesFor(meld.fromRiver).add(meld.calledTile);
    if (meld.ownerRiver == InputTarget.ownRiver) {
      final concealedTiles = List<Tile>.from(meld.tiles)
        ..remove(meld.calledTile);
      situation.hand.addAll(concealedTiles);
      _sortHand();
    }
    clearHistory();
    return true;
  }

  /// 指定した位置の牌を削除します。削除できた場合は true を返します。
  bool removeAt(InputTarget target, int index) {
    final tiles = situation.tilesFor(target);
    if (index < 0 || index >= tiles.length) return false;
    tiles.removeAt(index);
    return true;
  }

  /// 最後の有効な追加操作を取り消します。取り消せた場合は true を返します。
  bool undo() {
    return undoLastAddition() != null;
  }

  /// 最後の有効な追加を取り消し、追加されていた入力先を返します。
  InputTarget? undoLastAddition() {
    while (_history.isNotEmpty) {
      final action = _history.removeLast();
      final tiles = situation.tilesFor(action.target);
      final index = tiles.lastIndexOf(action.tile);
      if (index != -1) {
        tiles.removeAt(index);
        final handIndex = action.handIndex;
        if (handIndex != null) {
          final restoredIndex = handIndex > situation.hand.length
              ? situation.hand.length
              : handIndex;
          situation.hand.insert(restoredIndex, action.tile);
          _sortHand();
        }
        return action.target;
      }
    }
    return null;
  }

  /// 以降の入力だけを取り消し対象にするため、操作履歴を空にします。
  void clearHistory() => _history.clear();

  /// 取り消せる追加操作があるかを返します。
  bool get canUndo => _history.any(
    (action) => situation.tilesFor(action.target).contains(action.tile),
  );

  /// 手牌を萬子、筒子、索子、字牌の標準順へ並べ替えます。
  void _sortHand() => situation.hand.sort(
    (first, second) => first.index.compareTo(second.index),
  );

  /// 自分の手牌から副露に必要な牌の位置を重複なく探します。
  List<int> _matchingHandIndices(List<Tile> requiredTiles) {
    final available = List<bool>.filled(situation.hand.length, true);
    final indices = <int>[];
    for (final tile in requiredTiles) {
      final index = List.generate(situation.hand.length, (value) => value)
          .firstWhere(
            (value) => available[value] && situation.hand[value] == tile,
            orElse: () => -1,
          );
      if (index == -1) return const [];
      available[index] = false;
      indices.add(index);
    }
    indices.sort();
    return indices;
  }

  /// 相手の未確認手牌を公開しても同種牌4枚制限を超えないか確認します。
  bool _canExposeOpponentMeld(Tile calledTile, List<Tile> meldTiles) {
    for (final tile in meldTiles.toSet()) {
      final removedFromRiver = tile == calledTile ? 1 : 0;
      final exposed = meldTiles.where((item) => item == tile).length;
      if (situation.count(tile) - removedFromRiver + exposed >
          maxCopiesPerTile) {
        return false;
      }
    }
    return true;
  }

  /// 指定牌構成が選択した副露種別として成立するか確認します。
  bool _isValidMeld(MeldType type, Tile calledTile, List<Tile> tiles) {
    if (!tiles.contains(calledTile)) return false;
    return switch (type) {
      MeldType.pon =>
        tiles.length == 3 && tiles.every((tile) => tile == calledTile),
      MeldType.kan =>
        tiles.length == 4 && tiles.every((tile) => tile == calledTile),
      MeldType.chi => _isValidSequence(tiles),
    };
  }

  /// 3枚が同じ数牌種の連続した順子か確認します。
  bool _isValidSequence(List<Tile> tiles) {
    if (tiles.length != 3 || tiles.any((tile) => tile.index >= 27)) {
      return false;
    }
    final indices = tiles.map((tile) => tile.index).toList()..sort();
    return indices.first ~/ 9 == indices.last ~/ 9 &&
        indices[1] == indices[0] + 1 &&
        indices[2] == indices[1] + 1;
  }
}

/// 取り消し対象となる牌の追加操作です。
class _InputAction {
  /// 指定した入力先への通常の追加操作を生成します。
  const _InputAction.addition(this.target, this.tile) : handIndex = null;

  /// 手牌から自分の河への打牌操作を生成します。
  const _InputAction.discard(this.tile, this.handIndex)
    : target = InputTarget.ownRiver;

  final InputTarget target;
  final Tile tile;

  /// 打牌前に牌があった手牌内の位置です。通常の追加操作では null です。
  final int? handIndex;
}
