import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maohjong/main.dart';

void main() {
  testWidgets('相手の牌を長押しして手出しとリーチを記録し分析画面で確認できる', (tester) async {
    await tester.pumpWidget(const MaohjongApp());

    await tester.tap(find.byKey(const Key('setupTarget-doraIndicators')));
    await tester.pump();
    await _showTilePalette(tester);
    await tester.tap(find.byKey(const Key('palette-p9')));
    await tester.pump();
    await _showInputAreas(tester);
    await tester.tap(find.byKey(const Key('setupTarget-hand')));
    await tester.pump();
    await _showTilePalette(tester);
    await tester.tap(find.byKey(const Key('palette-m1')));
    await tester.pump();

    final startButton = find.byKey(const Key('startButton'));
    await tester.ensureVisible(startButton);
    await tester.tap(startButton);
    await tester.pump();
    await _showStartedTile(tester, 'p1');
    await tester.tap(find.byKey(const Key('palette-p1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('handTile-0')));
    await tester.pump();

    await _showStartedTile(tester, 'm2');
    await tester.longPress(find.byKey(const Key('palette-m2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('discardSourceSelector')), findsOneWidget);
    await tester.tap(find.text('手出し'));
    await tester.tap(find.byKey(const Key('riichiDiscardSwitch')));
    await tester.tap(find.byKey(const Key('saveDiscardMetadataButton')));
    await tester.pumpAndSettle();

    await _showInputAreas(tester);
    final analysisButton = find.byKey(const Key('dangerAnalysisButton'));
    await tester.ensureVisible(analysisButton);
    await tester.tap(analysisButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('下家'));
    await tester.tap(find.text('狙い役・待ち'));
    await tester.pumpAndSettle();

    final recordedMetadata = find.text('手出し・リーチ宣言牌');
    await tester.scrollUntilVisible(
      recordedMetadata,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(recordedMetadata, findsOneWidget);
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

/// 対局開始後の内部スクロールで指定牌を操作可能な位置へ表示します。
Future<void> _showStartedTile(WidgetTester tester, String tileName) async {
  await tester.scrollUntilVisible(
    find.byKey(Key('palette-$tileName')),
    80,
    scrollable: _startedPaletteScrollable(),
  );
  await tester.pumpAndSettle();
}

/// 局面入力画面本体の縦スクロール要素を返します。
Finder _verticalScrollable() => find.byWidgetPredicate(
  (widget) =>
      widget is Scrollable && widget.axisDirection == AxisDirection.down,
);

/// 対局開始後の牌パレット専用スクロール要素を返します。
Finder _startedPaletteScrollable() => find.descendant(
  of: find.byKey(const Key('tilePalettePanel')),
  matching: find.byType(Scrollable),
);
