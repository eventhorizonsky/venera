part of 'components.dart';

class BlurEffect extends StatelessWidget {
  final Widget child;

  final double blur;

  final BorderRadius? borderRadius;

  const BlurEffect({
    required this.child,
    this.borderRadius,
    this.blur = 15,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.zero;

    // blur <= 0 时直接不建图层。
    //
    // BackdropFilter 即使 sigma 传 0，框架仍会为它开一个 saveLayer（整块区域
    // 拷贝 + 合成）。调用方经常用 blur: 0 表示"这一帧不需要模糊"
    // （例如 Appbar 未滚动时、SliverAppbar 贴在顶部时），但旧实现照样建了
    // BackdropFilter，于是这笔钱每帧都在白付。这里直接短路掉。
    if (blur <= 0) {
      if (borderRadius == null) {
        return child;
      }
      return ClipRRect(borderRadius: radius, child: child);
    }

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: blur,
          sigmaY: blur,
          tileMode: TileMode.mirror,
        ),
        child: child,
      ),
    );
  }
}
