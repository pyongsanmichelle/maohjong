import 'package:flutter/material.dart';

/// 対局開始後の主要操作を1行に保ち、補助操作をメニューへまとめます。
class MatchActionBar extends StatelessWidget {
  /// 対局中の操作可否と既存処理へのコールバックを受け取ります。
  const MatchActionBar({
    super.key,
    required this.canUndo,
    required this.showCall,
    required this.showSelfKan,
    required this.onUndo,
    required this.onCall,
    required this.onSelfKan,
    required this.onRoundEnd,
    required this.onCorrectSituation,
    required this.onAddDora,
    required this.onOpenAnalysis,
    required this.onReturnToSetup,
  });

  /// Materialの最小タップ領域を満たす固定バー高です。
  static const double height = 48;

  /// 取り消せる操作が残っているかどうかです。
  final bool canUndo;

  /// 直前の打牌に対する鳴き操作を表示するかどうかです。
  final bool showCall;

  /// 自分の手番で行えるカン操作を表示するかどうかです。
  final bool showSelfKan;

  /// 最後の入力を取り消す処理です。
  final VoidCallback onUndo;

  /// 鳴き選択を開始する処理です。
  final VoidCallback onCall;

  /// 自分のカン選択を開始する処理です。
  final VoidCallback onSelfKan;

  /// 現在局の終了選択を開始する処理です。
  final VoidCallback onRoundEnd;

  /// 局面補正を開始する処理です。
  final VoidCallback onCorrectSituation;

  /// ドラ表示牌を追加する処理です。
  final VoidCallback onAddDora;

  /// 相手分析画面を開く処理です。
  final VoidCallback onOpenAnalysis;

  /// 入力済み局面を保持して準備画面へ戻る処理です。
  final VoidCallback onReturnToSetup;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const Key('matchActionBar'),
    height: height,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _MatchToolbarButton(
            key: const Key('undoButton'),
            label: '取り消し',
            icon: Icons.undo,
            onPressed: canUndo ? onUndo : null,
          ),
          if (showCall)
            _MatchToolbarButton(
              key: const Key('callButton'),
              label: 'チー・ポン・カン',
              icon: Icons.call_split,
              emphasized: true,
              onPressed: onCall,
            ),
          if (showSelfKan)
            _MatchToolbarButton(
              key: const Key('selfKanButton'),
              label: '自分のカン',
              icon: Icons.view_module,
              emphasized: true,
              onPressed: onSelfKan,
            ),
          _MatchToolbarButton(
            key: const Key('roundEndButton'),
            label: '局終了',
            icon: Icons.sports_score,
            emphasized: true,
            onPressed: onRoundEnd,
          ),
          const Spacer(),
          _MatchMoreMenu(
            onCorrectSituation: onCorrectSituation,
            onAddDora: onAddDora,
            onOpenAnalysis: onOpenAnalysis,
            onReturnToSetup: onReturnToSetup,
          ),
        ],
      ),
    ),
  );
}

/// アクションバー上で48×48の操作領域と日本語案内を保証します。
class _MatchToolbarButton extends StatelessWidget {
  /// 表示内容と操作可否を受け取ってアイコンボタンを生成します。
  const _MatchToolbarButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.emphasized = false,
  });

  /// Tooltipと読み上げに使う操作名です。
  final String label;

  /// 操作を表すMaterialアイコンです。
  final IconData icon;

  /// タップ時の処理です。nullの場合は無効状態になります。
  final VoidCallback? onPressed;

  /// 文脈依存または局進行の主要操作として強調するかどうかです。
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    enabled: onPressed != null,
    label: label,
    child: ExcludeSemantics(
      child: emphasized
          ? IconButton.filledTonal(
              tooltip: label,
              onPressed: onPressed,
              icon: Icon(icon),
            )
          : IconButton(tooltip: label, onPressed: onPressed, icon: Icon(icon)),
    ),
  );
}

/// その他メニューで識別する補助操作です。
enum _MatchMoreAction { correctSituation, addDora, openAnalysis, returnToSetup }

/// 利用頻度の低い対局操作を、文字付きメニューとして提供します。
class _MatchMoreMenu extends StatelessWidget {
  /// メニューから呼び出す既存処理を受け取ります。
  const _MatchMoreMenu({
    required this.onCorrectSituation,
    required this.onAddDora,
    required this.onOpenAnalysis,
    required this.onReturnToSetup,
  });

  /// 局面補正を開始する処理です。
  final VoidCallback onCorrectSituation;

  /// ドラ表示牌を追加する処理です。
  final VoidCallback onAddDora;

  /// 相手分析画面を開く処理です。
  final VoidCallback onOpenAnalysis;

  /// 準備画面へ戻る処理です。
  final VoidCallback onReturnToSetup;

  /// 選択した項目に対応する既存処理を呼び出します。
  void _select(_MatchMoreAction action) {
    switch (action) {
      case _MatchMoreAction.correctSituation:
        onCorrectSituation();
      case _MatchMoreAction.addDora:
        onAddDora();
      case _MatchMoreAction.openAnalysis:
        onOpenAnalysis();
      case _MatchMoreAction.returnToSetup:
        onReturnToSetup();
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    label: 'その他の対局操作',
    child: ExcludeSemantics(
      child: PopupMenuButton<_MatchMoreAction>(
        key: const Key('matchMoreMenuButton'),
        tooltip: 'その他の対局操作',
        icon: const Icon(Icons.more_vert),
        onSelected: _select,
        itemBuilder: (context) => const [
          PopupMenuItem(
            key: Key('kanCorrectionButton'),
            value: _MatchMoreAction.correctSituation,
            child: _MatchMenuLabel(
              icon: Icons.view_module_outlined,
              label: '局面補正',
            ),
          ),
          PopupMenuItem(
            key: Key('addDoraButton'),
            value: _MatchMoreAction.addDora,
            child: _MatchMenuLabel(icon: Icons.add_box_outlined, label: 'ドラ追加'),
          ),
          PopupMenuItem(
            key: Key('dangerAnalysisButton'),
            value: _MatchMoreAction.openAnalysis,
            child: _MatchMenuLabel(icon: Icons.shield_outlined, label: '相手分析'),
          ),
          PopupMenuDivider(),
          PopupMenuItem(
            key: Key('returnToSetupButton'),
            value: _MatchMoreAction.returnToSetup,
            child: _MatchMenuLabel(icon: Icons.settings, label: '設定に戻る'),
          ),
        ],
      ),
    ),
  );
}

/// その他メニュー内でアイコンと日本語ラベルを横並びにします。
class _MatchMenuLabel extends StatelessWidget {
  /// メニュー項目のアイコンと表示名を受け取ります。
  const _MatchMenuLabel({required this.icon, required this.label});

  /// 操作を表すMaterialアイコンです。
  final IconData icon;

  /// 利用者へ表示する日本語の操作名です。
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 20),
      const SizedBox(width: 12),
      Flexible(child: Text(label)),
    ],
  );
}
