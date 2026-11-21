part of 'components.dart';

/// 加载骨架的静态占位容器。
///
/// 替代 `package:shimmer_animation`。**刻意不含任何动画**。
///
/// 历史与理由：
///
/// 1. 原包 `_ShimmerAnimatorState` 在动画 listener 里直接 `setState(() {})`，
///    每帧重建整棵骨架子树（详情页是几百个 Container/Row/Column）。
///
/// 2. 改成自实现的动画版后，实测（--profile-frames）显示：
///      build(UI线程) 平均 0.48ms  —— 说明重建问题已解决
///      raster(光栅)   p50 64ms / p90 187ms / max 296ms —— 光栅仍然炸
///    骨架期间的发光绘制（整页渐变 + 覆盖层）在光栅线程上代价极高，
///    1600x1000 窗口下 p90 就接近 200ms，体感就是转场卡死。
///
/// 3. 因此这里彻底去掉流光动画：骨架只在数据未就绪时静态显示，
///    不产生任何逐帧重绘。加载完成后骨架被真实内容替换。
///
/// 加载态本来就是一个短暂的过渡，静态骨架在体验上完全够用，
/// 换来的是转场期间零额外光栅开销。
class SkeletonShimmer extends StatelessWidget {
  const SkeletonShimmer({
    super.key,
    required this.child,
    this.color = Colors.white,
    this.opacity = 0.3,
  });

  /// 骨架内容。
  final Widget child;

  /// 保留字段以兼容调用点；静态骨架不产生流光，故不再使用。
  final Color color;

  /// 保留字段以兼容调用点。
  final double opacity;

  @override
  Widget build(BuildContext context) {
    // 直接返回骨架本体：无 CustomPaint、无 shader、无 Ticker、无逐帧重绘。
    return child;
  }
}
