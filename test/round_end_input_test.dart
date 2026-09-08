import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maohjong/main.dart';

void main() {
  testWidgets('局終了をキャンセルしてから下家のツモ上がりで次局へ進める', (tester) async {
    await tester.pumpWidget(const MaohjongApp());
    await _prepareAndStart(tester);

    await _openRoundEndDialog(tester);
    expect(find.text('簡易進行のため、親の連荘と点数計算は行いません。'), findsOneWidget);
    await tester.tap(find.byKey(const Key('roundEndWinner-lower')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('cancelRoundEndButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('roundEndDialog')), findsNothing);
    expect(find.byKey(const Key('roundEndButton')), findsOneWidget);

    await tester.tap(find.byKey(const Key('roundEndButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('roundEndWinner-lower')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirmRoundEndButton')));
    await tester.pumpAndSettle();

    expect(find.text('ツモ：下家が和了。東2局へ進みました。手牌とドラを入力してください。'), findsOneWidget);
    expect(find.text('東2局・1巡目'), findsOneWidget);
    expect(find.text('0/13枚'), findsOneWidget);
  });

  testWidgets('ロンは直前打牌がある場合だけ選べ放銃者を自動表示する', (tester) async {
    await tester.pumpWidget(const MaohjongApp());
    await tester.tap(find.byKey(const Key('dealer-lower')));
    await tester.pump();
    await _prepareAndStart(tester);

    await _openRoundEndDialog(tester);
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('roundEndType-ron')))
          .onSelected,
      isNull,
    );
    expect(find.text('ロンは直前の打牌がある場合だけ選択できます。'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cancelRoundEndButton')));
    await tester.pumpAndSettle();

    await _showTilePalette(tester);
    await tester.scrollUntilVisible(
      find.byKey(const Key('palette-s3')),
      50,
      scrollable: _startedPaletteScrollable(),
    );
    await tester.tap(find.byKey(const Key('palette-s3')));
    await tester.pump();
    await _openRoundEndDialog(tester);
    await tester.tap(find.byKey(const Key('roundEndType-ron')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('roundEndWinner-across')));
    await tester.pump();

    expect(find.text('放銃者：下家（直前の打牌から自動判定）'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirmRoundEndButton')));
    await tester.pumpAndSettle();

    expect(
      find.text('ロン：対面が和了（放銃：下家）。東2局へ進みました。手牌とドラを入力してください。'),
      findsOneWidget,
    );
  });
}

/// 最小限の手牌とドラを入力して対局を開始します。
Future<void> _prepareAndStart(WidgetTester tester) async {
  await _showInputAreas(tester);
  await tester.tap(find.byKey(const Key('setupTarget-hand')));
  await tester.pump();
  await _showTilePalette(tester);
  await tester.tap(find.byKey(const Key('palette-m1')));
  await tester.pump();
  await _showInputAreas(tester);
  await tester.tap(find.byKey(const Key('setupTarget-doraIndicators')));
  await tester.pump();
  await _showTilePalette(tester);
  await tester.tap(find.byKey(const Key('palette-p9')));
  await tester.pump();
  await _showInputAreas(tester);
  final startButton = find.byKey(const Key('startButton'));
  await tester.ensureVisible(startButton);
  await tester.tap(startButton);
  await tester.pump();
}

/// 対局中の局終了ボタンを表示してダイアログを開きます。
Future<void> _openRoundEndDialog(WidgetTester tester) async {
  final button = find.byKey(const Key('roundEndButton'));
  await tester.scrollUntilVisible(
    button,
    -300,
    scrollable: _verticalScrollable(),
  );
  await tester.tap(button);
  await tester.pumpAndSettle();
}

/// 牌パレットまでスクロールします。
Future<void> _showTilePalette(WidgetTester tester) async {
  if (find.byKey(const Key('startedTableLayout')).evaluate().isNotEmpty) {
    await tester.scrollUntilVisible(
      find.byKey(const Key('palette-m1')),
      80,
      scrollable: _startedPaletteScrollable(),
    );
  } else {
    await tester.scrollUntilVisible(
      find.byKey(const Key('palette-red')),
      300,
      scrollable: _verticalScrollable(),
    );
  }
  await tester.pumpAndSettle();
}

/// 画面上部の入力領域までスクロールします。
Future<void> _showInputAreas(WidgetTester tester) async {
  if (find.byKey(const Key('startedTableLayout')).evaluate().isNotEmpty) {
    await tester.pumpAndSettle();
    return;
  }
  await tester.scrollUntilVisible(
    find.textContaining('局・'),
    -300,
    scrollable: _verticalScrollable(),
  );
  await tester.pumpAndSettle();
}

/// 画面本体の縦スクロール要素を返します。
Finder _verticalScrollable() => find.byWidgetPredicate(
  (widget) =>
      widget is Scrollable && widget.axisDirection == AxisDirection.down,
);

/// 対局開始後の牌パレット専用スクロール要素を返します。
Finder _startedPaletteScrollable() => find.descendant(
  of: find.byKey(const Key('tilePalettePanel')),
  matching: find.byType(Scrollable),
);
