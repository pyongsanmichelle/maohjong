import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maohjong/main.dart';

void main() {
  testWidgets('開始前は東1局を表示し手牌と最初のドラだけを入力する', (tester) async {
    await tester.pumpWidget(const MaohjongApp());

    expect(find.text('東1局・1巡目'), findsOneWidget);
    expect(find.byKey(const Key('kyokuSelector')), findsNothing);
    expect(find.byKey(const Key('turnSelector')), findsNothing);
    expect(find.text('南場'), findsNothing);
    expect(find.byKey(const Key('setupTarget-hand')), findsOneWidget);
    expect(find.byKey(const Key('setupTarget-doraIndicators')), findsOneWidget);
    expect(find.byKey(const Key('setupActive-hand')), findsOneWidget);
    expect(find.byKey(const Key('setupKanButton')), findsNothing);
    expect(find.text('取り消し'), findsNothing);
    for (final target in [
      'hand',
      'ownRiver',
      'upperRiver',
      'acrossRiver',
      'lowerRiver',
      'doraIndicators',
    ]) {
      expect(find.byKey(Key('targetTab-$target')), findsNothing);
    }
  });

  testWidgets('領域タップで入力先を切り替え最初のドラは1枚に制限する', (tester) async {
    await tester.pumpWidget(const MaohjongApp());
    await _showPalette(tester);
    await tester.tap(find.byKey(const Key('palette-m1')));
    await tester.pump();
    expect(find.byKey(const Key('handTile-0')), findsOneWidget);

    await _showTop(tester);
    await tester.tap(find.byKey(const Key('setupTarget-doraIndicators')));
    await tester.pump();
    expect(find.byKey(const Key('setupActive-doraIndicators')), findsOneWidget);
    await _showPalette(tester);
    await tester.tap(find.byKey(const Key('palette-p9')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('palette-p8')));
    await tester.pump();

    expect(find.textContaining('開始前のドラ表示牌は1枚です'), findsOneWidget);
    await _showTop(tester);
    expect(find.byKey(const Key('setupDoraTile-0')), findsOneWidget);
    await tester.tap(find.byKey(const Key('setupDoraTile-0')));
    await tester.pump();
    expect(find.byKey(const Key('setupDoraTile-0')), findsNothing);
  });

  testWidgets('不足理由を表示し手牌とドラ入力後に開始できる', (tester) async {
    await tester.pumpWidget(const MaohjongApp());
    expect(find.text('自分の手牌を入力してください。'), findsOneWidget);

    await _prepareAndStart(tester, dealer: 'lower');

    expect(find.byKey(const Key('startedTableLayout')), findsOneWidget);
    expect(find.text('対局入力中：下家の河を選択'), findsOneWidget);
    expect(find.byKey(const Key('undoButton')), findsOneWidget);
    expect(find.byKey(const Key('matchMoreMenuButton')), findsOneWidget);
    await _openMatchMoreMenu(tester);
    expect(find.byKey(const Key('kanCorrectionButton')), findsOneWidget);
    expect(find.byKey(const Key('addDoraButton')), findsOneWidget);
  });

  testWidgets('開始後は追加ドラを選び卓上から訂正できる', (tester) async {
    await tester.pumpWidget(const MaohjongApp());
    await _prepareAndStart(tester);

    await _openMatchMoreMenu(tester);
    await tester.tap(find.byKey(const Key('addDoraButton')));
    await tester.pumpAndSettle();
    final sheetPalette = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byKey(const Key('palette-s9')),
    );
    await tester.tap(sheetPalette);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tableTile-doraIndicators-1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('tableTile-doraIndicators-1')));
    await tester.pump();
    expect(find.byKey(const Key('tableTile-doraIndicators-1')), findsNothing);
  });

  testWidgets('自分のツモ前は固定手牌から打牌できない', (tester) async {
    await tester.pumpWidget(const MaohjongApp());
    await _prepareAndStart(tester);

    expect(find.text('対局入力中：ツモ牌を選択'), findsOneWidget);
    await tester.tap(find.byKey(const Key('handTile-0')));
    await tester.pump();
    expect(find.text('先にツモ牌を選択してください。'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('palette-p1')),
      100,
      scrollable: _startedPaletteScrollable(),
    );
    await tester.tap(find.byKey(const Key('palette-p1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('handTile-0')));
    await tester.pump();
    expect(find.text('対局入力中：下家の河を選択'), findsOneWidget);
  });

  testWidgets('数牌のパレットは横一列に9枚表示する', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaohjongApp());
    await _showPalette(tester);

    final first = tester.getTopLeft(find.byKey(const Key('palette-m1')));
    final last = tester.getTopRight(find.byKey(const Key('palette-m9')));
    expect(last.dy, first.dy);
    expect(last.dx, lessThanOrEqualTo(344));
  });
}

/// 最小限の手牌と最初のドラを入力して対局を開始します。
Future<void> _prepareAndStart(
  WidgetTester tester, {
  String dealer = 'self',
}) async {
  if (dealer != 'self') {
    await tester.tap(find.byKey(Key('dealer-$dealer')));
    await tester.pump();
  }
  await _showPalette(tester);
  await tester.tap(find.byKey(const Key('palette-m1')));
  await tester.pump();
  await _showTop(tester);
  await tester.tap(find.byKey(const Key('setupTarget-doraIndicators')));
  await tester.pump();
  await _showPalette(tester);
  await tester.tap(find.byKey(const Key('palette-p9')));
  await tester.pump();
  await _showTop(tester);
  final start = find.byKey(const Key('startButton'));
  await tester.ensureVisible(start);
  await tester.tap(start);
  await tester.pumpAndSettle();
}

/// 現在の画面にある牌パレットまでスクロールします。
Future<void> _showPalette(WidgetTester tester) async {
  final started = find
      .byKey(const Key('startedTableLayout'))
      .evaluate()
      .isNotEmpty;
  await tester.scrollUntilVisible(
    find.byKey(const Key('palette-m1')),
    80,
    scrollable: started ? _startedPaletteScrollable() : _verticalScrollable(),
  );
  await tester.pumpAndSettle();
}

/// 開始前の入力領域まで戻します。
Future<void> _showTop(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const Key('setupRoundStatus')),
    -300,
    scrollable: _verticalScrollable(),
  );
  await tester.pumpAndSettle();
}

/// 開始前画面の縦スクロール要素を返します。
Finder _verticalScrollable() => find.byWidgetPredicate(
  (widget) =>
      widget is Scrollable && widget.axisDirection == AxisDirection.down,
);

/// 開始後の牌パレット専用スクロール要素を返します。
Finder _startedPaletteScrollable() => find.descendant(
  of: find.byKey(const Key('tilePalettePanel')),
  matching: find.byType(Scrollable),
);

/// 対局中のその他メニューを開きます。
Future<void> _openMatchMoreMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('matchMoreMenuButton')));
  await tester.pumpAndSettle();
}
