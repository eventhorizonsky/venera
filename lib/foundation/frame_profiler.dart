import 'package:flutter/scheduler.dart';
import 'package:venera/foundation/log.dart';

/// 逐帧耗时探针（诊断用，默认关闭）。
///
/// 只在启动参数带 `--profile-frames` 时启用。日志写到 App 的 logs.txt。
///
/// 记录两类信息，缺一不可：
///
/// 1. **单帧耗时**（build / raster）——区分是 UI 线程（widget 重建、布局、
///    同步 JS）还是光栅线程（saveLayer、模糊）超时。
///
/// 2. **帧间隔（gap）**——这一类更关键。如果 UI 线程被一段同步逻辑占住，
///    这一帧根本走不完，`addTimingsCallback` 就不会回调，于是"完全不出帧"
///    的严重卡顿在只看单帧耗时时**完全看不到**（表现为"日志里什么都没记，
///    但画面确实卡住了"）。这里用相邻两次回调的时间差来捕捉空窗。
class FrameProfiler {
  FrameProfiler._();

  static bool _enabled = false;

  /// 单帧 build 或 raster 超过此值则记录。
  static const double _thresholdMs = 20.0;

  /// 相邻帧间隔超过此值则记录（说明中间有长任务阻塞 UI 线程）。
  static const double _gapThresholdMs = 50.0;

  static const int _maxRecords = 600;

  static int _count = 0;

  static int _gapCount = 0;

  /// 上一次收到 timings 回调的时刻，用于算帧间隔。
  static int? _lastCallbackUs;

  static bool get enabled => _enabled;

  static void install(List<String> args) {
    if (!args.contains('--profile-frames')) return;
    _enabled = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    Log.info('FrameProfile', 'frame profiler enabled (gap+frame)');
  }

  static void _onTimings(List<FrameTiming> timings) {
    if (_count >= _maxRecords && _gapCount >= _maxRecords) return;

    // ---- 帧间隔：捕捉"长时间没有新帧" ----
    final nowUs = DateTime.now().microsecondsSinceEpoch;
    final last = _lastCallbackUs;
    _lastCallbackUs = nowUs;
    if (last != null) {
      final gapMs = (nowUs - last) / 1000.0;
      if (gapMs >= _gapThresholdMs && _gapCount < _maxRecords) {
        _gapCount++;
        Log.info(
          'FrameProfile',
          'GAP#$_gapCount ${gapMs.toStringAsFixed(1)}ms 无新帧 '
              '(batch=${timings.length})',
        );
      }
    }

    // ---- 单帧耗时 ----
    for (final t in timings) {
      if (_count >= _maxRecords) return;
      final build = t.buildDuration.inMicroseconds / 1000.0;
      final raster = t.rasterDuration.inMicroseconds / 1000.0;
      final total = t.totalSpan.inMicroseconds / 1000.0;
      if (build < _thresholdMs && raster < _thresholdMs) continue;
      _count++;
      // UI 线程(build) 与 光栅线程(raster) 对应完全不同的修法：
      // 前者是 widget 重建/布局/同步JS，后者是 saveLayer/模糊/大面积绘制。
      final culprit = build >= raster ? 'UI_THREAD' : 'RASTER_THREAD';
      Log.info(
        'FrameProfile',
        'frame#$_count $culprit '
            'build=${build.toStringAsFixed(1)}ms '
            'raster=${raster.toStringAsFixed(1)}ms '
            'total=${total.toStringAsFixed(1)}ms',
      );
    }
  }
}
