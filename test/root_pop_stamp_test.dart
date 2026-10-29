import 'package:flutter_test/flutter_test.dart';

import 'package:venera/foundation/root_pop_stamp.dart';

/// 这套状态存在的唯一目的：安卓**手势返回**（预测式返回）一次只退一层。
///
/// 根因回顾：预测式返回的手势检测器是每个 Route 各挂一份，启用条件是
/// `route.isCurrent && route.popGestureEnabled`，而系统手势广播给所有
/// 注册者。两层 Navigator 并存时（根层 [MainPage, Reader]、内层
/// [列表页, ComicPage]），详情页在内层里依然是 isCurrent，于是阅读器和
/// 详情页的检测器同时启用 —— 一次侧滑各 pop 一次，越过了详情页。
///
/// AppPageRoute 用 RootPopStamp.hasRouteAbove 让内层路由在手势开始时
/// 让位，所以这里的语义必须钉住。
void main() {
  setUp(() => RootPopStamp.resetForTest());

  group('RootPopStamp', () {
    test('初始状态：根层没有页面压着', () {
      expect(RootPopStamp.hasRouteAbove, isFalse);
      expect(RootPopStamp.consumedRecently(), isFalse);
    });

    test('压上阅读器后 hasRouteAbove 为真并通知重建', () {
      RootPopStamp.setHasRouteAbove(true);
      expect(RootPopStamp.hasRouteAbove, isTrue);
      expect(RootPopStamp.revision.value, 1);
    });

    test('重复设置同一值不重复通知', () {
      RootPopStamp.setHasRouteAbove(true);
      final after = RootPopStamp.revision.value;
      RootPopStamp.setHasRouteAbove(true);
      expect(RootPopStamp.revision.value, after);
    });

    test('阅读器退出后恢复为假', () {
      RootPopStamp.setHasRouteAbove(true);
      RootPopStamp.setHasRouteAbove(false);
      expect(RootPopStamp.hasRouteAbove, isFalse);
    });

    test('刚 pop 过一层时 consumedRecently 为真', () {
      expect(RootPopStamp.consumedRecently(), isFalse);
      RootPopStamp.mark();
      expect(RootPopStamp.consumedRecently(), isTrue);
    });
  });
}
