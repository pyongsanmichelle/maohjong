import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maohjong/domain/game_situation.dart';
import 'package:maohjong/domain/tile.dart';
import 'package:maohjong/main.dart';
import 'package:maohjong/presentation/danger_analysis_page.dart';

void main() {
  testWidgets('相手を切り替えて牌ごとの理由を確認できる', (tester) async {
    final situation = GameSituation()
      ..hand.addAll([Tile.m1, Tile.p2, Tile.s3])
      ..upperRiver.add(Tile.m1)
      ..doraIndicators.add(Tile.p1);

    await tester.pumpWidget(
      MaterialApp(home: DangerAnalysisPage(situation: situation)),
    );

    expect(find.byKey(const Key('dangerNotice')), findsOneWidget);
    expect(find.byKey(const Key('dangerTile-m1')), findsOneWidget);
    expect(find.textContaining('現物'), findsOneWidget);

    await tester.tap(find.byKey(const Key('dangerTile-p2')));
    await tester.pump();
    expect(find.textContaining('ドラです'), findsOneWidget);

    await tester.tap(find.text('対面'));
    await tester.pump();
    expect(find.byKey(const Key('opponentInformationWarning')), findsOneWidget);
    expect(find.textContaining('強い安全材料'), findsOneWidget);
  });

  testWidgets('危険度順へ切り替えると高得点の牌を先頭にする', (tester) async {
    final situation = GameSituation()
      ..hand.addAll([Tile.m1, Tile.p2])
      ..upperRiver.add(Tile.m1)
      ..doraIndicators.add(Tile.p1);

    await tester.pumpWidget(
      MaterialApp(home: DangerAnalysisPage(situation: situation)),
    );
    final safeBefore = tester.getTopLeft(
      find.byKey(const Key('dangerTile-m1')),
    );
    final dangerBefore = tester.getTopLeft(
      find.byKey(const Key('dangerTile-p2')),
    );
    expect(safeBefore.dx, lessThan(dangerBefore.dx));

    await tester.tap(find.text('危険度順'));
    await tester.pump();

    final dangerAfter = tester.getTopLeft(
      find.byKey(const Key('dangerTile-p2')),
    );
    final safeAfter = tester.getTopLeft(find.byKey(const Key('dangerTile-m1')));
    expect(dangerAfter.dx, lessThan(safeAfter.dx));
  });

  testWidgets('360px幅では最大7枚を同じ行に表示する', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final situation = GameSituation()..hand.addAll(Tile.values.take(8));

    await tester.pumpWidget(
      MaterialApp(home: DangerAnalysisPage(situation: situation)),
    );

    final first = tester.getTopLeft(find.byKey(const Key('dangerTile-m1')));
    final seventh = tester.getTopLeft(find.byKey(const Key('dangerTile-m7')));
    final eighth = tester.getTopLeft(find.byKey(const Key('dangerTile-m8')));
    expect(first.dy, seventh.dy);
    expect(eighth.dy, greaterThan(first.dy));
  });

  testWidgets('手牌が空の場合は入力を促す', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: DangerAnalysisPage(situation: GameSituation())),
    );

    expect(find.byKey(const Key('dangerEmptyHand')), findsOneWidget);
    expect(find.text('手牌を入力してください。'), findsOneWidget);
  });

  testWidgets('対局開始後に局面入力画面から守備分析を開ける', (tester) async {
    await tester.pumpWidget(const MaohjongApp());

    await tester.tap(find.byKey(const Key('targetTab-doraIndicators')));
    await tester.pump();
    await _showTilePalette(tester);
    await tester.tap(find.byKey(const Key('palette-p9')));
    await tester.pump();
    await _showInputAreas(tester);
    await tester.tap(find.byKey(const Key('targetTab-hand')));
    await tester.pump();
    await _showTilePalette(tester);
    await tester.tap(find.byKey(const Key('palette-m1')));
    await tester.pump();
    final startButton = find.byKey(const Key('startButton'));
    await tester.ensureVisible(startButton);
    await tester.tap(startButton);
    await tester.pump();

    final analysisButton = find.byKey(const Key('dangerAnalysisButton'));
    await tester.ensureVisible(analysisButton);
    await tester.tap(analysisButton);
    await tester.pumpAndSettle();

    expect(find.text('守備分析'), findsOneWidget);
    expect(find.byKey(const Key('dangerTile-m1')), findsOneWidget);
  });
}

/// 画面下部の牌パレットまでスクロールします。
Future<void> _showTilePalette(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const Key('palette-red')),
    300,
    scrollable: _verticalScrollable(),
  );
  await tester.pumpAndSettle();
}

/// 画面上部の入力領域までスクロールします。
Future<void> _showInputAreas(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('東1局・1巡目'),
    -300,
    scrollable: _verticalScrollable(),
  );
  await tester.pumpAndSettle();
}

/// 局面入力画面本体の縦スクロール要素を返します。
Finder _verticalScrollable() => find.byWidgetPredicate(
  (widget) =>
      widget is Scrollable && widget.axisDirection == AxisDirection.down,
);
