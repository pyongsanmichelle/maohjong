import 'package:flutter/material.dart';

import '../domain/tile.dart';

/// 牌の表示名を返します。
String tileLabel(Tile tile) => const [
  '1萬',
  '2萬',
  '3萬',
  '4萬',
  '5萬',
  '6萬',
  '7萬',
  '8萬',
  '9萬',
  '1筒',
  '2筒',
  '3筒',
  '4筒',
  '5筒',
  '6筒',
  '7筒',
  '8筒',
  '9筒',
  '1索',
  '2索',
  '3索',
  '4索',
  '5索',
  '6索',
  '7索',
  '8索',
  '9索',
  '東',
  '南',
  '西',
  '北',
  '白',
  '發',
  '中',
][tile.index];

/// 牌種別に応じた文字色を返します。
Color tileColor(Tile tile) => tile.index < 9
    ? Colors.red.shade700
    : tile.index < 18
    ? Colors.blue.shade700
    : tile.index < 27
    ? Colors.green.shade700
    : tile == Tile.red
    ? Colors.red.shade700
    : Colors.black87;
