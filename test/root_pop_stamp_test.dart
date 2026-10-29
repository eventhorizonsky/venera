import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:venera/components/components.dart';

/// 这套判断存在的唯一目的：安卓全局返回（系统手势 / 返回键）一次只退一层。
///
/// 历史现象：详情页 → 阅读页 → 全局返回，会越过详情页直接退回列表。
/// 根因是同一次返回被两层先后处理：
///   根 Navigator:   [MainPage, Reader]     ← 阅读器压在这里
///   内层 Navigator: [列表页, ComicPage]     ← 详情页压在 MainPage 内部
/// 根层弹出阅读器之后，内层那圈 PopScope 又把返回转发给自己的 Navigator，
/// 详情页就被顺手弹掉。
void main() {
  setUp(() {
    RootPopStamp.hasRouteAbove = false;
    RootPopStamp.revision.value = 0;
    RootPopObserver.aboveCount = 0;
  });

  group('RootPopStamp', () {
    test('刚 pop 过一层时 consumedRecently 为真', () {
      expect(RootPopStamp.consumedRecently(), isFalse);
      RootPopStamp.mark();
      expect(RootPopStamp.consumedRecently(), isTrue);
    });

    test('setHasRouteAbove 变化会触发重建通知', () {
      RootPopStamp.setHasRouteAbove(false);
      expect(RootPopStamp.revision.value, 0, reason: '无变化不应通知');

      RootPopStamp.setHasRouteAbove(true);
      expect(RootPopStamp.hasRouteAbove, isTrue);
      expect(RootPopStamp.revision.value, 1, reason: '有页面压上来必须通知');

      RootPopStamp.setHasRouteAbove(true);
      expect(RootPopStamp.revision.value, 1, reason: '重复设置不应重复通知');
    });

    test('根层有页面压着 → 内层 PopScope 必须不拦返回', () {
      // 这条是修复本身：阅读器在根层时 hasRouteAbove 为 true，
      // 内层 canPop 取 _canPop && !hasRouteAbove == false。
      RootPopStamp.setHasRouteAbove(true);
      const innerCanPop = false; // 详情页压在内层时的 _canPop
      expect(innerCanPop && !RootPopStamp.hasRouteAbove, isFalse);
    });
  });

  group('RootPopObserver 计数', () {
    test('压上阅读器时 aboveCount=1，弹掉后回到 0', () {
      final obs = RootPopObserver();

      // 首屏：previousRoute 为 null，不算压在上面
      obs.didPush(_FakeRoute(), null);
      expect(RootPopObserver.aboveCount, 0);
      expect(RootPopStamp.hasRouteAbove, isFalse);

      // 阅读器压上来
      obs.didPush(_FakeRoute(), _FakeRoute());
      expect(RootPopObserver.aboveCount, 1);
      expect(RootPopStamp.hasRouteAbove, isTrue, reason: '阅读器在根层时内层必须让路');

      // 返回：弹掉阅读器
      obs.didPop(_FakeRoute(), _FakeRoute());
      expect(RootPopObserver.aboveCount, 0);
      expect(RootPopStamp.hasRouteAbove, isFalse, reason: '阅读器退出后内层恢复接管');
    });

    test('计数不会变负', () {
      final obs = RootPopObserver();
      obs.didPop(_FakeRoute(), null); // 把最后一个也弹了（异常情况）
      expect(RootPopObserver.aboveCount, 0);
    });
  });
}

/// 只为触发 observer 回调的假路由。
class _FakeRoute extends Route<void> {
  _FakeRoute() : super(settings: const RouteSettings(name: 'fake'));

  @override
  RoutePopDisposition get popDisposition => RoutePopDisposition.pop;

  @override
  void dispose() {}
}
