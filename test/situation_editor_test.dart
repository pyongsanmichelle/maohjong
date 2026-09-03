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
}
