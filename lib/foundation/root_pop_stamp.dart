import 'package:flutter/foundation.dart';

/// 根 Navigator 上是否压着页面（阅读器、弹层页等）。
///
/// 为什么需要这个东西放在 foundation 层：预测式返回的手势检测器是
/// **每个 Route 各挂一份**，启用条件只看该 Route 在自己 Navigator 里是否
/// isCurrent（见 Flutter 的 _PredictiveBackGestureDetectorState._isEnabled）。
///
/// 本 App 有两层 Navigator：
///   根层:   [MainPage, Reader]
///   内层:   [列表页, ComicPage]      ← 详情页
/// 阅读器压在根层时，详情页在内层里**依然是 isCurrent**，于是两个检测器
/// 同时启用。系统的手势事件广播给所有注册者 —— 一次侧滑，阅读器和详情页
/// 各 pop 一次，用户看到的就是"从阅读页返回越过详情页直接退回列表"。
/// 按键返回不走预测式通道，所以只有手势路径出问题。
///
/// AppPageRoute 需要读这个状态来决定内层路由是否参与预测式返回，因此
/// 它必须待在 foundation 层（components 依赖 foundation，不能反向）。
class RootPopStamp {
  RootPopStamp._();

  static DateTime? _last;

  static const _window = Duration(milliseconds: 400);

  /// 根层是否有路由压在 MainPage 之上。
  static bool hasRouteAbove = false;

  /// 变化通知，让相关 Widget（NaviPane 的 PopScope）重建。
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// 由根 Navigator 的 observer 调用。
  static void setHasRouteAbove(bool value) {
    if (value == hasRouteAbove) return;
    hasRouteAbove = value;
    revision.value++;
  }

  /// 由根 Navigator 的 observer 在每次 didPop 时调用。
  static void mark() => _last = DateTime.now();

  /// 根层是否刚弹过一层（即当前这次返回大概已经被消费掉了）。
  static bool consumedRecently() {
    final last = _last;
    if (last == null) return false;
    return DateTime.now().difference(last) < _window;
  }

  /// 仅供测试重置。
  @visibleForTesting
  static void resetForTest() {
    _last = null;
    hasRouteAbove = false;
    revision.value = 0;
  }
}
