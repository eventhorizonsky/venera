part of 'components.dart';

/// 加载骨架的流光（shimmer）效果。
///
/// 替代 `package:shimmer_animation`。换掉的唯一原因是**性能**：
/// 那个包的 `_ShimmerAnimatorState` 在动画 listener 里直接
/// `setState(() {})`，也就是说**每一帧都重建整棵骨架子树**
/// （详情页的骨架是几百个 Container/Row/Column）。
///
/// 实测表现：只在"有 loading 骨架"的路径上卡（详情页首次加载），
/// 而 NAS 离线命中、元数据秒回、骨架根本没机会出现的路径完全不卡。
/// 骨架本身在转场期还叠着页面滑入动画，两个动画一起每帧重建整棵树，
/// 掉帧被放大到 70~190ms/帧。
///
/// 这里的实现把"动画值的变化"限制在**一个 CustomPaint 内部**：
///   - 用 [AnimatedBuilder] 只重建 CustomPaint 这一层，不碰 child；
///   - child 通过 builder 的 `child` 参数传入，Flutter 会原样复用，不重建；
///   - painter 的 shouldRepaint 只在动画值/颜色真的变化时返回 true。
///
/// 结果：骨架子树在整个动画期间**一次都不重建**，每帧的开销退化为
/// "重绘一个纯渐变色块"，与子树规模无关。
class SkeletonShimmer extends StatefulWidget {
  const SkeletonShimmer({
    super.key,
    required this.child,
    this.color = Colors.white,
    this.opacity = 0.3,
    this.duration = const Duration(milliseconds: 1500),
    this.interval = Duration.zero,
    this.enabled = true,
  });

  /// 被罩上流光的骨架内容。**不会被重建**。
  final Widget child;

  /// 流光颜色。
  final Color color;

  /// 流光峰值不透明度。
  final double opacity;

  /// 单次扫过所需时间。
  final Duration duration;

  /// 两次扫过之间的间隔。
  final Duration interval;

  /// 是否启用流光动画。
  ///
  /// 设为 false 时**完全不建 CustomPaint、不跑 Ticker**，只原样返回 child。
  /// 用于对照实验：确认骨架的发光绘制是不是光栅线程(raster)超时的来源。
  final bool enabled;

  @override
  State<SkeletonShimmer> createState() => _SkeletonShimmerState();
}

class _SkeletonShimmerState extends State<SkeletonShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  late final Animation<double> _animation = CurvedAnimation(
    parent: _controller,
    // 与原包一致：前 60% 完成扫过，剩余时间留白，观感上更像"呼吸"
    curve: const Interval(0, 0.6, curve: Curves.decelerate),
  );

  void _onStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      // 扫完一遍后按 interval 重新开始。
      // 用 Timer 而不是 repeat()，是为了保留原包的间隔语义。
      _restartTimer?.cancel();
      _restartTimer = Timer(widget.interval, () {
        if (mounted) _controller.forward(from: 0);
      });
    }
  }

  Timer? _restartTimer;

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener(_onStatusChanged);
    _controller.forward();
  }

  @override
  void dispose() {
    _restartTimer?.cancel();
    _restartTimer = null;
    _controller.removeStatusListener(_onStatusChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 对照实验用：关掉后不建 CustomPaint、不跑动画，只返回骨架本体。
    if (!widget.enabled) return widget.child;

    // 关键：**不要用 CustomPaint(foregroundPainter)**。
    //
    // foregroundPainter 要求 CustomPaint 先把 child 完整画出来，再在其上叠前景，
    // 这会让整棵骨架子树每帧被迫走 saveLayer（整页大小），于是每一帧都要
    // 重新光栅化整片骨架。实测（1600x1000，debug，--profile-frames）：
    //   foregroundPainter 方案：raster = 64 / 90 / 171 / 151 / 208 / 216 / 126 ms
    //   （关掉 shimmer 的对照组：raster 最高仅 31ms）
    // 216ms/帧 = 4.6fps，正是"卡死"的观感来源。
    //
    // 改成「两层」结构：
    //   1. 骨架本体包进 RepaintBoundary —— 只画一次进图层，动画期间完全不重绘；
    //   2. 流光作为一个独立的透明图层叠在上面，每帧只重绘这一层的小色块。
    return Stack(
      children: [
        // 骨架本体：稳定图层，不参与逐帧重绘
        RepaintBoundary(child: widget.child),
        // 流光覆盖层：只有它在动
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _animation,
              builder: (context, _) {
                return CustomPaint(
                  painter: _SkeletonShimmerPainter(
                    position: _animation.value,
                    color: widget.color,
                    opacity: widget.opacity,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _SkeletonShimmerPainter extends CustomPainter {
  const _SkeletonShimmerPainter({
    required this.position,
    required this.color,
    required this.opacity,
  });

  final double position;
  final Color color;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    // 与原包 _CustomSplashAnimation 的几何一致：
    // 一条斜向渐变色带从左上扫到右下，带宽约为中心位置的 ±20%。
    const bandWidth = 0.2;
    final stops = <double>[
      0.0,
      position,
      (position + bandWidth) > 1 ? 1.0 : position + bandWidth,
      (position + bandWidth * 2) > 1 ? 1.0 : position + bandWidth * 2,
      1.0,
    ];

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        tileMode: TileMode.decal,
        begin: Alignment.topLeft,
        end: Alignment.centerRight,
        stops: stops,
        colors: [
          Colors.transparent,
          color.withValues(alpha: 0.05),
          color.withValues(alpha: opacity),
          color.withValues(alpha: 0.05),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromLTRB(
          size.width * -0.5,
          size.height > size.width ? 0 : size.height * -0.5,
          size.width * 1.5,
          size.height * 1.5,
        ),
      );

    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_SkeletonShimmerPainter oldDelegate) {
    // 只有动画值变了才重绘（颜色/透明度变化也要）。
    return oldDelegate.position != position ||
        oldDelegate.color != color ||
        oldDelegate.opacity != opacity;
  }
}
