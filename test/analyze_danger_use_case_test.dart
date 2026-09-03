import 'package:flutter_test/flutter_test.dart';
import 'package:maohjong/application/analyze_danger_use_case.dart';
import 'package:maohjong/domain/game_situation.dart';
import 'package:maohjong/domain/opponent.dart';
import 'package:maohjong/domain/tile.dart';

void main() {
  test('危険度順は高得点を先にし同点を牌の標準順にする', () {
    final situation = GameSituation()
      ..hand.addAll([Tile.m3, Tile.m1, Tile.m2])
      ..upperRiver.add(Tile.m1)
      ..doraIndicators.add(Tile.m1);

    const useCase = AnalyzeDangerUseCase();
    final result = useCase(
      situation: situation,
      opponent: Opponent.upper,
      sortOrder: DangerSortOrder.danger,
    );

    expect(result.map((item) => item.tile), [Tile.m2, Tile.m3, Tile.m1]);
    expect(result.last.score, 0);
  });

  test('手牌順はスコアにかかわらず牌の標準順にする', () {
    final situation = GameSituation()
      ..hand.addAll([Tile.p3, Tile.m9, Tile.m1])
      ..upperRiver.add(Tile.m1);

    const useCase = AnalyzeDangerUseCase();
    final result = useCase(
      situation: situation,
      opponent: Opponent.upper,
      sortOrder: DangerSortOrder.hand,
    );

    expect(result.map((item) => item.tile), [Tile.m1, Tile.m9, Tile.p3]);
  });
}
