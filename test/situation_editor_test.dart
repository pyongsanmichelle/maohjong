import 'package:flutter_test/flutter_test.dart';
import 'package:maohjong/domain/game_situation.dart';
import 'package:maohjong/domain/meld.dart';
import 'package:maohjong/domain/situation_editor.dart';
import 'package:maohjong/domain/tile.dart';

void main() {
  test('手牌と複数ドラ表示牌から未確認枚数を計算する', () {
    final editor = SituationEditor(GameSituation());

    expect(editor.remainingCopies(Tile.m1), 4);
    expect(editor.add(InputTarget.hand, Tile.m1), isTrue);
    expect(editor.add(InputTarget.doraIndicators, Tile.m1), isTrue);
    expect(editor.add(InputTarget.doraIndicators, Tile.m1), isTrue);
    expect(editor.remainingCopies(Tile.m1), 1);
    expect(editor.add(InputTarget.doraIndicators, Tile.m1), isTrue);
    expect(editor.remainingCopies(Tile.m1), 0);
    expect(editor.add(InputTarget.hand, Tile.m1), isFalse);
  });

  test('自分の河も未確認枚数に反映する', () {
    final editor = SituationEditor(GameSituation());

    expect(editor.add(InputTarget.ownRiver, Tile.p1), isTrue);
    expect(editor.situation.ownRiver, [Tile.p1]);
    expect(editor.remainingCopies(Tile.p1), 3);
  });

  test('手牌へ追加するたびに牌種と数字の順へ自動整列する', () {
    final editor = SituationEditor(GameSituation());

    expect(editor.add(InputTarget.hand, Tile.red), isTrue);
    expect(editor.add(InputTarget.hand, Tile.s9), isTrue);
    expect(editor.add(InputTarget.hand, Tile.m3), isTrue);
    expect(editor.add(InputTarget.hand, Tile.m1), isTrue);
    expect(editor.add(InputTarget.hand, Tile.p5), isTrue);

    expect(editor.situation.hand, [
      Tile.m1,
      Tile.m3,
      Tile.p5,
      Tile.s9,
      Tile.red,
    ]);
  });

  test('手牌からの打牌を取り消すと元の位置へ戻す', () {
    final situation = GameSituation()..hand.addAll([Tile.m1, Tile.m2, Tile.m3]);
    final editor = SituationEditor(situation);

    expect(editor.discardFromHand(1), isTrue);
    expect(situation.hand, [Tile.m1, Tile.m3]);
    expect(situation.ownRiver, [Tile.m2]);
    expect(editor.undoLastAddition(), InputTarget.ownRiver);
    expect(situation.hand, [Tile.m1, Tile.m2, Tile.m3]);
    expect(situation.ownRiver, isEmpty);
  });

  test('相手のポンは河から副露へ移し削除時に河へ戻す', () {
    final situation = GameSituation()..ownRiver.add(Tile.p5);
    final editor = SituationEditor(situation);

    final meld = editor.declareMeld(
      type: MeldType.pon,
      callerRiver: InputTarget.acrossRiver,
      fromRiver: InputTarget.ownRiver,
      calledTile: Tile.p5,
      tiles: [Tile.p5, Tile.p5, Tile.p5],
    );

    expect(meld, isNotNull);
    expect(situation.ownRiver, isEmpty);
    expect(situation.melds.single.tiles, [Tile.p5, Tile.p5, Tile.p5]);
    expect(situation.count(Tile.p5), 3);
    expect(editor.removeMeld(meld!), isTrue);
    expect(situation.ownRiver, [Tile.p5]);
    expect(situation.melds, isEmpty);
  });

  test('自分のチーは必要牌を手牌から副露へ移す', () {
    final situation = GameSituation()
      ..hand.addAll([Tile.m1, Tile.m2, Tile.p9])
      ..upperRiver.add(Tile.m3);
    final editor = SituationEditor(situation);

    final meld = editor.declareMeld(
      type: MeldType.chi,
      callerRiver: InputTarget.ownRiver,
      fromRiver: InputTarget.upperRiver,
      calledTile: Tile.m3,
      tiles: [Tile.m1, Tile.m2, Tile.m3],
    );

    expect(meld, isNotNull);
    expect(situation.hand, [Tile.p9]);
    expect(situation.upperRiver, isEmpty);
    expect(situation.melds.single.tiles, [Tile.m1, Tile.m2, Tile.m3]);
    expect(editor.removeMeld(meld!), isTrue);
    expect(situation.hand, [Tile.m1, Tile.m2, Tile.p9]);
    expect(situation.upperRiver, [Tile.m3]);
  });

  test('開始時点のカンは4枚を見えている牌として登録し訂正できる', () {
    final situation = GameSituation();
    final editor = SituationEditor(situation);

    final meld = editor.registerSetupKan(
      ownerRiver: InputTarget.acrossRiver,
      tile: Tile.s7,
      type: KanType.open,
    );

    expect(meld, isNotNull);
    expect(meld!.origin, MeldOrigin.setup);
    expect(meld.kanType, KanType.open);
    expect(meld.tiles, List.filled(4, Tile.s7));
    expect(editor.remainingCopies(Tile.s7), 0);
    expect(
      editor.registerSetupKan(
        ownerRiver: InputTarget.upperRiver,
        tile: Tile.s7,
        type: KanType.concealed,
      ),
      isNull,
    );

    expect(editor.removeMeld(meld), isTrue);
    expect(situation.melds, isEmpty);
    expect(editor.remainingCopies(Tile.s7), 4);
  });

  test('自分の番は手牌4枚から暗槓し取り消すと手牌へ戻る', () {
    final situation = GameSituation()..hand.addAll(List.filled(4, Tile.m9));
    final editor = SituationEditor(situation);

    expect(editor.selfKanOptions, hasLength(1));
    final option = editor.selfKanOptions.single;
    expect(option.tile, Tile.m9);
    expect(option.type, KanType.concealed);

    final meld = editor.declareSelfKan(option);

    expect(meld, isNotNull);
    expect(situation.hand, isEmpty);
    expect(meld!.origin, MeldOrigin.selfKan);
    expect(meld.kanType, KanType.concealed);
    expect(editor.removeMeld(meld), isTrue);
    expect(situation.hand, List.filled(4, Tile.m9));
    expect(situation.melds, isEmpty);
  });

  test('自分のポンと手牌1枚から加槓し取り消すとポンへ戻る', () {
    final situation = GameSituation()
      ..hand.addAll([Tile.p5, Tile.p5])
      ..upperRiver.add(Tile.p5);
    final editor = SituationEditor(situation);
    final pon = editor.declareMeld(
      type: MeldType.pon,
      callerRiver: InputTarget.ownRiver,
      fromRiver: InputTarget.upperRiver,
      calledTile: Tile.p5,
      tiles: List.filled(3, Tile.p5),
    );
    expect(pon, isNotNull);
    expect(editor.add(InputTarget.hand, Tile.p5), isTrue);

    final option = editor.selfKanOptions.single;
    expect(option.type, KanType.added);
    final kan = editor.declareSelfKan(option);

    expect(kan, isNotNull);
    expect(situation.hand, isEmpty);
    expect(situation.melds.single.type, MeldType.kan);
    expect(situation.melds.single.kanType, KanType.added);

    expect(editor.removeMeld(kan!), isTrue);
    expect(situation.hand, [Tile.p5]);
    expect(situation.melds.single.type, MeldType.pon);
    expect(situation.melds.single.fromRiver, InputTarget.upperRiver);
  });
}
