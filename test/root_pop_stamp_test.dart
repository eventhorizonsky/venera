import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:venera/components/components.dart';

/// 这套判断存在的唯一目的：安卓全局返回（系统手势 / 返回键）一次只退一层。
///
/// 历史现象：详情页 → 阅读页 → 全局返回，会越过详情页直接退回列表。
/// 原因是阅读器压在根 Navigator 上、详情页压在内层 Navigator 上，
/// 同一次返回事件被两层先后处理。
void main() {
  group('RootPopStamp', () {
    setUp(() {
      RootPopStamp.hasRouteAbove = false;
      RootPopStamp.revision.value = 0;
    });

    test('刚 pop 过一层时 consumedRecently 为真', () {
      expect(RootPopStamp.consumedRecently(), isFalse);
      RootPopStamp.mark();
      expect(RootPopStamp.consumedRecently(), isTrue);
    });

    test('hasRouteAbove 变化会触发重建通知', () {
      final nav = _FakeNavigatorState(canPopValue: false);

      RootPopStamp.sync(nav);
      expect(RootPopStamp.hasRouteAbove, isFalse);
      expect(RootPopStamp.revision.value, 0, reason: '无变化不应通知');

      nav.canPopValue = true;
      RootPopStamp.sync(nav);
      expect(RootPopStamp.hasRouteAbove, isTrue);
      expect(RootPopStamp.revision.value, 1, reason: '有页面压上来必须通知');

      RootPopStamp.sync(nav);
      expect(RootPopStamp.revision.value, 1, reason: '重复同步不应重复通知');
    });

    test('根层有页面压着 → 内层 PopScope 必须不拦返回', () {
      // 这条是修复本身：阅读器在根层时 hasRouteAbove 为 true，
      // 内层 canPop 取 _canPop && !hasRouteAbove == false。
      RootPopStamp.hasRouteAbove = true;
      const innerCanPop = false; // 详情页压在内层时的 _canPop
      expect(innerCanPop && !RootPopStamp.hasRouteAbove, isFalse);

      // 阅读器退掉之后，内层恢复正常的拦截职责
      RootPopStamp.hasRouteAbove = false;
      expect(innerCanPop && !RootPopStamp.hasRouteAbove, isFalse,
          reason: '详情页还在时，内层仍应拦返回并自己处理');
    });
  });
}

/// 只用来控制 canPop() 返回值的 NavigatorState 替身。
class _FakeNavigatorState extends NavigatorState {
  _FakeNavigatorState({required this.canPopValue});

  bool canPopValue;

  @override
  bool canPop() => canPopValue;
}
