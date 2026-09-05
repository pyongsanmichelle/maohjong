import 'package:flutter_test/flutter_test.dart';
import 'package:maohjong/domain/danger_analyzer.dart';
import 'package:maohjong/domain/danger_assessment.dart';
import 'package:maohjong/domain/game_situation.dart';
import 'package:maohjong/domain/meld.dart';
import 'package:maohjong/domain/opponent.dart';
import 'package:maohjong/domain/tile.dart';

void main() {
  group('DangerAnalyzer', () {
    const analyzer = DangerAnalyzer();

    test('手牌の牌種を重複なく標準順で評価する', () {
      final situation = GameSituation()
        ..hand.addAll([Tile.s3, Tile.m1, Tile.m1, Tile.p2]);

      final result = analyzer.analyze(situation, Opponent.upper);

      expect(result.map((item) => item.tile), [Tile.m1, Tile.p2, Tile.s3]);
    });

    test('対象相手の河にある牌を現物としてスコア0にする', () {
      final situation = GameSituation()
        ..hand.addAll([Tile.m1, Tile.p1])
        ..upperRiver.add(Tile.m1)
        ..acrossRiver.add(Tile.p1);

      final upper = analyzer.analyze(situation, Opponent.upper);
      final across = analyzer.analyze(situation, Opponent.across);

      expect(_assessment(upper, Tile.m1).score, 0);
      expect(
        _codes(_assessment(upper, Tile.m1)),
        contains(DangerReasonCode.genbutsu),
      );
      expect(_assessment(upper, Tile.p1).score, isNot(0));
      expect(_assessment(across, Tile.p1).score, 0);
    });

    test('鳴かれて河から消えた牌も現物と筋の履歴に使う', () {
      final situation = GameSituation()
        ..hand.addAll([Tile.m1, Tile.m4])
        ..melds.add(
          Meld(
            type: MeldType.pon,
            ownerRiver: InputTarget.lowerRiver,
            tiles: const [Tile.m1, Tile.m1, Tile.m1],
            calledTile: Tile.m1,
            fromRiver: InputTarget.upperRiver,
          ),
        );

      final result = analyzer.analyze(situation, Opponent.upper);

      expect(_assessment(result, Tile.m1).score, 0);
      expect(
        _codes(_assessment(result, Tile.m1)),
        contains(DangerReasonCode.genbutsu),
      );
      expect(
        _codes(_assessment(result, Tile.m4)),
        contains(DangerReasonCode.suji),
      );
    });

    test('同じ牌が4枚見えている場合はスコア0にする', () {
      final situation = GameSituation()
        ..hand.addAll([Tile.p5, Tile.p5])
        ..ownRiver.add(Tile.p5)
        ..lowerRiver.add(Tile.p5);

      final result = analyzer.analyze(situation, Opponent.upper);

      expect(_assessment(result, Tile.p5).score, 0);
      expect(
        _codes(_assessment(result, Tile.p5)),
        contains(DangerReasonCode.allCopiesVisible),
      );
    });

    test('端側の筋と両筋を異なる重みで評価する', () {
      final situation = GameSituation()
        ..hand.addAll([Tile.m1, Tile.m4])
        ..upperRiver.addAll([Tile.m1, Tile.m4, Tile.m7]);

      final result = analyzer.analyze(situation, Opponent.upper);

      final edge = _assessment(result, Tile.m1);
      final middle = _assessment(result, Tile.m4);
      expect(edge.score, 0, reason: '河にある牌は筋より現物を優先する');
      expect(_codes(middle), contains(DangerReasonCode.genbutsu));

      final sujiOnly = GameSituation()
        ..hand.addAll([Tile.m1, Tile.m4])
        ..upperRiver.addAll([Tile.m4, Tile.m7]);
      final sujiResult = analyzer.analyze(sujiOnly, Opponent.upper);
      expect(_assessment(sujiResult, Tile.m1).score, 40);
      expect(
        _codes(_assessment(sujiResult, Tile.m1)),
        contains(DangerReasonCode.suji),
      );
      expect(_assessment(sujiResult, Tile.m4).score, 0);

      final full = GameSituation()
        ..hand.add(Tile.m4)
        ..upperRiver.addAll([Tile.m1, Tile.m7]);
      final fullResult = analyzer.analyze(full, Opponent.upper);
      expect(_assessment(fullResult, Tile.m4).score, 30);
      expect(
        _codes(_assessment(fullResult, Tile.m4)),
        contains(DangerReasonCode.fullSuji),
      );
    });

    test('壁とワンチャンスを重複せず評価する', () {
      final wall = GameSituation()
        ..hand.add(Tile.m1)
        ..ownRiver.addAll(List.filled(4, Tile.m2))
        ..lowerRiver.addAll(List.filled(3, Tile.m3));

      final wallResult = analyzer.analyze(wall, Opponent.upper);

      expect(_assessment(wallResult, Tile.m1).score, 30);
      expect(_codes(_assessment(wallResult, Tile.m1)), [DangerReasonCode.kabe]);

      final oneChance = GameSituation()
        ..hand.add(Tile.m1)
        ..ownRiver.addAll(List.filled(3, Tile.m2));
      final oneChanceResult = analyzer.analyze(oneChance, Opponent.upper);
      expect(_assessment(oneChanceResult, Tile.m1).score, 45);
      expect(
        _codes(_assessment(oneChanceResult, Tile.m1)),
        contains(DangerReasonCode.oneChance),
      );
    });

    test('字牌の見えている枚数を評価へ反映する', () {
      final situation = GameSituation()
        ..hand.addAll([Tile.east, Tile.east])
        ..ownRiver.add(Tile.east);

      final result = analyzer.analyze(situation, Opponent.upper);

      expect(_assessment(result, Tile.east).score, 35);
      expect(_assessment(result, Tile.east).reasons.single.evidenceCount, 3);
    });

    test('数牌・風牌・三元牌のドラを循環して求める', () {
      expect(DangerAnalyzer.doraForIndicator(Tile.m9), Tile.m1);
      expect(DangerAnalyzer.doraForIndicator(Tile.p9), Tile.p1);
      expect(DangerAnalyzer.doraForIndicator(Tile.s9), Tile.s1);
      expect(DangerAnalyzer.doraForIndicator(Tile.north), Tile.east);
      expect(DangerAnalyzer.doraForIndicator(Tile.red), Tile.white);
    });

    test('複数の同じドラ表示牌を重複して加点する', () {
      final situation = GameSituation()
        ..hand.add(Tile.m1)
        ..doraIndicators.addAll([Tile.m9, Tile.m9]);

      final result = analyzer.analyze(situation, Opponent.upper);
      final assessment = _assessment(result, Tile.m1);

      expect(assessment.score, 80);
      expect(assessment.level, DangerLevel.danger);
      expect(assessment.reasons.single.evidenceCount, 2);
    });

    test('対象相手の同色副露が2組以上なら同色牌を加点する', () {
      final situation = GameSituation()
        ..hand.addAll([Tile.m7, Tile.p7])
        ..melds.addAll([
          _chi(
            owner: InputTarget.upperRiver,
            tiles: const [Tile.m1, Tile.m2, Tile.m3],
          ),
          _chi(
            owner: InputTarget.upperRiver,
            tiles: const [Tile.m4, Tile.m5, Tile.m6],
          ),
        ]);

      final result = analyzer.analyze(situation, Opponent.upper);

      expect(_assessment(result, Tile.m7).score, 60);
      expect(
        _codes(_assessment(result, Tile.m7)),
        contains(DangerReasonCode.openSuitPressure),
      );
      expect(
        _codes(_assessment(result, Tile.p7)),
        isNot(contains(DangerReasonCode.openSuitPressure)),
      );
    });

    test('同じ牌が5枚以上ある不正局面を拒否する', () {
      final situation = GameSituation()..hand.addAll(List.filled(5, Tile.red));

      expect(
        () => analyzer.analyze(situation, Opponent.upper),
        throwsA(isA<DangerAnalysisException>()),
      );
    });

    test('分析前後で局面を変更しない', () {
      final situation = GameSituation()
        ..hand.addAll([Tile.m2, Tile.m1])
        ..upperRiver.add(Tile.m4);
      final handBefore = List<Tile>.from(situation.hand);
      final riverBefore = List<Tile>.from(situation.upperRiver);

      analyzer.analyze(situation, Opponent.upper);

      expect(situation.hand, handBefore);
      expect(situation.upperRiver, riverBefore);
    });

    test('危険度の境界値を3段階へ変換する', () {
      expect(DangerAnalyzer.levelForScore(25), DangerLevel.safe);
      expect(DangerAnalyzer.levelForScore(26), DangerLevel.caution);
      expect(DangerAnalyzer.levelForScore(59), DangerLevel.caution);
      expect(DangerAnalyzer.levelForScore(60), DangerLevel.danger);
    });
  });
}

DangerAssessment _assessment(List<DangerAssessment> assessments, Tile tile) =>
    assessments.singleWhere((assessment) => assessment.tile == tile);

List<DangerReasonCode> _codes(DangerAssessment assessment) =>
    assessment.reasons.map((reason) => reason.code).toList();

Meld _chi({required InputTarget owner, required List<Tile> tiles}) => Meld(
  type: MeldType.chi,
  ownerRiver: owner,
  tiles: tiles,
  calledTile: tiles.first,
  fromRiver: InputTarget.lowerRiver,
);
