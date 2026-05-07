// lib/widgets/image_viewer.dart
//
// Full-screen swipeable image viewer
// ────────────────────────────────────────────────────────
//
// Usage:
//   ImageViewer.show(
//     context,
//     imageIds: note.imageIds,
//     initialIndex: tappedIndex,
//     getImage: (id) => Provider.of<NotesProvider>(context, listen: false).getImage(id),
//   );
//
// ✅ PageView swipe between images
// ✅ InteractiveViewer pinch-to-zoom & pan per page
// ✅ Swipe-down to dismiss (drag anywhere downward when not zoomed)
// ✅ Page counter (1 / N) and dot indicators for ≤ 8 images
// ✅ Overlay auto-hides after 3 s, tap to reveal
// ✅ Close button (top-left)
// ✅ Hero animation on the tapped thumbnail
// ✅ Loading spinner while image decodes
// ✅ Black background, status bar hidden
// ✅ base64 decoded once per image and cached — no main-thread decode on rebuild
// ✅ RepaintBoundary per page — zoom on one page never invalidates others
// ✅ Zoom state in ValueNotifier — only PageView physics rebuilds, not whole tree

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../language.dart';

// Top-level function required by compute() — must not be a closure or method.
Uint8List? _decodeBase64Isolate(String b64) {
  try {
    return base64Decode(b64);
  } catch (_) {
    return null;
  }
}

// ── Gesture recognizer that yields to multi-pointer (pinch) gestures ──────────
//
// The outer vertical-drag handler for swipe-to-dismiss must not steal the
// gesture arena from InteractiveViewer when two or more fingers are down.
// A standard GestureDetector's VerticalDragGestureRecognizer wins the arena
// before InteractiveViewer's ScaleGestureRecognizer can establish itself.
//
// Solution: subclass VerticalDragGestureRecognizer and call rejectGesture()
// on ourselves as soon as a second pointer appears. That immediately frees
// the arena so InteractiveViewer can take over for pinch-to-zoom / pan.

class _DismissOnlyDragRecognizer extends VerticalDragGestureRecognizer {
  _DismissOnlyDragRecognizer({super.debugOwner});

  final Set<int> _activePointers = {};

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _activePointers.add(event.pointer);
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _activePointers.remove(event.pointer);
    }
    // If a second finger is down, reject ourselves so InteractiveViewer wins.
    if (_activePointers.length > 1) {
      stopTrackingPointer(event.pointer);
      resolve(GestureDisposition.rejected);
      return;
    }
    super.handleEvent(event);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _activePointers.remove(pointer);
    super.didStopTrackingLastPointer(pointer);
  }
}

// ── Zoom-aware physics ────────────────────────────────────────────────────────

class _ZoomAwareScrollPhysics extends ScrollPhysics {
  final bool isZoomed;
  const _ZoomAwareScrollPhysics({required this.isZoomed, super.parent});

  @override
  _ZoomAwareScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _ZoomAwareScrollPhysics(
          isZoomed: isZoomed, parent: buildParent(ancestor));

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    if (isZoomed) return 0.0;
    return super.applyPhysicsToUserOffset(position, offset);
  }

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    if (isZoomed) return value - position.pixels;
    return super.applyBoundaryConditions(position, value);
  }

  @override
  bool get allowImplicitScrolling => !isZoomed;
}

// ── Single image page ─────────────────────────────────────────────────────────

class _ImagePage extends StatefulWidget {
  final String imageId;
  final Uint8List? imageBytes;
  final bool isLoading;
  final TransformationController transformCtrl;
  final ValueChanged<bool> onZoomChanged;
  final VoidCallback onTap;

  const _ImagePage({
    required this.imageId,
    required this.imageBytes,
    required this.isLoading,
    required this.transformCtrl,
    required this.onZoomChanged,
    required this.onTap,
  });

  @override
  State<_ImagePage> createState() => _ImagePageState();
}

class _ImagePageState extends State<_ImagePage> {
  bool _wasZoomed = false;

  void _handleTransformChange() {
    final scale = widget.transformCtrl.value.getMaxScaleOnAxis();
    final isZoomed = scale > 1.01;
    if (isZoomed != _wasZoomed) {
      _wasZoomed = isZoomed;
      widget.onZoomChanged(isZoomed);
    }
  }

  @override
  void initState() {
    super.initState();
    widget.transformCtrl.addListener(_handleTransformChange);
  }

  @override
  void dispose() {
    widget.transformCtrl.removeListener(_handleTransformChange);
    super.dispose();
  }

  void _handleDoubleTap() {
    final scale = widget.transformCtrl.value.getMaxScaleOnAxis();
    if (scale > 1.01) {
      widget.transformCtrl.value = Matrix4.identity();
    } else {
      widget.transformCtrl.value = Matrix4.identity()
        ..scaleByDouble(2.5, 2.5, 1.0, 1.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);

    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTap: _handleDoubleTap,
      behavior: HitTestBehavior.opaque,
      child: RepaintBoundary(
        child: InteractiveViewer(
          transformationController: widget.transformCtrl,
          minScale: 1.0,
          maxScale: 5.0,
          clipBehavior: Clip.none,
          panAxis: PanAxis.free,
          panEnabled: true,
          scaleEnabled: true,
          child: Center(
            child: Hero(
              tag: 'note_image_${widget.imageId}',
              child: widget.isLoading
                  ? const _ShimmerPlaceholder()
                  : widget.imageBytes != null
                      ? Image.memory(
                          widget.imageBytes!,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                          cacheWidth:
                              (mq.size.width * mq.devicePixelRatio).toInt(),
                          errorBuilder: (_, __, ___) =>
                              const _BrokenImagePlaceholder(),
                        )
                      : const _BrokenImagePlaceholder(),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrokenImagePlaceholder extends StatelessWidget {
  const _BrokenImagePlaceholder();

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 120,
        height: 120,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.broken_image_outlined,
                color: Colors.white38, size: 48),
            const SizedBox(height: 8),
            Text(AppTranslations.translate('image_unavailable'),
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
          ],
        ),
      );
}

// ── Main viewer ───────────────────────────────────────────────────────────────

// ── Shimmer loading placeholder ───────────────────────────────────────────────
// Fixed to screen size so it always fills the viewer — no need to know the
// actual image dimensions in advance. The sweep animates across the full width.

class _ShimmerPlaceholder extends StatefulWidget {
  const _ShimmerPlaceholder();

  @override
  State<_ShimmerPlaceholder> createState() => _ShimmerPlaceholderState();
}

class _ShimmerPlaceholderState extends State<_ShimmerPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return SizedBox(
      width: size.width,
      height: size.height,
      child: AnimatedBuilder(
        animation: _anim,
        builder: (_, __) {
          // Sweep goes from -1 → 2 so the highlight fully enters and exits.
          final sweepX = (_anim.value * 3 - 1) * size.width;
          return CustomPaint(
            painter: _ShimmerPainter(
              sweepX: sweepX,
              width: size.width,
              height: size.height,
            ),
          );
        },
      ),
    );
  }
}

class _ShimmerPainter extends CustomPainter {
  final double sweepX;
  final double width;
  final double height;

  const _ShimmerPainter({
    required this.sweepX,
    required this.width,
    required this.height,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Base layer — dark ghost matching black background with a slight lift.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, height),
      Paint()..color = const Color(0xFF1A1A1A),
    );

    // Sweeping highlight — a soft vertical band travelling left to right.
    final sweepRect =
        Rect.fromLTWH(sweepX - width * 0.4, 0, width * 0.8, height);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, height),
      Paint()
        ..shader = const LinearGradient(
          colors: [
            Color(0x00FFFFFF),
            Color(0x10FFFFFF),
            Color(0x22FFFFFF),
            Color(0x10FFFFFF),
            Color(0x00FFFFFF),
          ],
          stops: [0.0, 0.3, 0.5, 0.7, 1.0],
        ).createShader(sweepRect),
    );

    // Corner bracket markers — subtle lines suggesting an image frame.
    final framePaint = Paint()
      ..color = const Color(0x20FFFFFF)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    const c = 28.0; // corner arm length
    const m = 40.0; // margin from edge

    void drawCorner(double x, double y, double dx, double dy) {
      canvas.drawLine(Offset(x, y + dy * c), Offset(x, y), framePaint);
      canvas.drawLine(Offset(x, y), Offset(x + dx * c, y), framePaint);
    }

    drawCorner(m, m, 1, 1); // top-left
    drawCorner(width - m, m, -1, 1); // top-right
    drawCorner(m, height - m, 1, -1); // bottom-left
    drawCorner(width - m, height - m, -1, -1); // bottom-right
  }

  @override
  bool shouldRepaint(_ShimmerPainter old) => old.sweepX != sweepX;
}

class ImageViewer extends StatefulWidget {
  final List<String> imageIds;
  final int initialIndex;
  final String? Function(String imageId) getImage;

  const ImageViewer._({
    required this.imageIds,
    required this.initialIndex,
    required this.getImage,
  });

  static void show(
    BuildContext context, {
    required List<String> imageIds,
    required int initialIndex,
    required String? Function(String imageId) getImage,
  }) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        barrierDismissible: true,
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, __, ___) => ImageViewer._(
          imageIds: imageIds,
          initialIndex: initialIndex,
          getImage: getImage,
        ),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: animation,
          child: child,
        ),
      ),
    );
  }

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer>
    with SingleTickerProviderStateMixin {
  late final PageController _pageCtrl;
  late int _currentIndex;
  late final List<TransformationController> _transforms;
  final ValueNotifier<bool> _isZoomed = ValueNotifier(false);

  // null = not yet decoded, Uint8List = decoded (empty on decode error)
  late final List<Uint8List?> _imageBytes;
  late final List<bool> _isDecoding;

  // ── Overlay visibility ────────────────────────────────────────────────────
  bool _overlayVisible = true;
  late final AnimationController _overlayAnim;
  late final Animation<double> _overlayFade;

  // ── Swipe-to-dismiss ─────────────────────────────────────────────────────
  double _dragY = 0.0;
  double _bgOpacity = 1.0;
  static const double _dismissThreshold = 120.0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageCtrl = PageController(initialPage: widget.initialIndex);

    _transforms = List.generate(
      widget.imageIds.length,
      (_) => TransformationController(),
    );

    _imageBytes = List.filled(widget.imageIds.length, null, growable: false);
    _isDecoding = List.filled(widget.imageIds.length, false, growable: false);

    _overlayAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: 1.0,
    );
    _overlayFade = CurvedAnimation(parent: _overlayAnim, curve: Curves.easeOut);

    // Only decode the initial image + immediate neighbors — decoding all at
    // once floods isolates and causes a noticeable slowdown with 5+ images.
    _decodeImageAt(widget.initialIndex).then((_) {
      final next = widget.initialIndex + 1;
      final prev = widget.initialIndex - 1;
      if (next < widget.imageIds.length) _decodeImageAt(next);
      if (prev >= 0) _decodeImageAt(prev);
    });

    _scheduleOverlayHide();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _overlayAnim.dispose();
    _isZoomed.dispose();
    _pageCtrl.dispose();
    for (final t in _transforms) {
      t.dispose();
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ── Decoding ──────────────────────────────────────────────────────────────

  Future<void> _decodeImageAt(int index) async {
    if (_imageBytes[index] != null || _isDecoding[index]) return;
    final b64 = widget.getImage(widget.imageIds[index]);
    if (b64 == null) return;
    if (mounted) setState(() => _isDecoding[index] = true);
    final bytes = await compute(_decodeBase64Isolate, b64);
    if (!mounted) return;
    setState(() {
      _imageBytes[index] = bytes;
      _isDecoding[index] = false;
    });
  }

  // ── Overlay ───────────────────────────────────────────────────────────────

  void _scheduleOverlayHide() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _overlayVisible) _hideOverlay();
    });
  }

  void _hideOverlay() {
    if (!_overlayVisible) return;
    _overlayVisible = false;
    _overlayAnim.reverse();
  }

  void _toggleOverlay() {
    if (_overlayVisible) {
      _hideOverlay();
    } else {
      _overlayVisible = true;
      _overlayAnim.forward();
      _scheduleOverlayHide();
    }
  }

  // ── Zoom ──────────────────────────────────────────────────────────────────

  void _close() => Navigator.of(context).pop();

  void _resetZoom(int index) {
    _transforms[index].value = Matrix4.identity();
    if (index == _currentIndex) _isZoomed.value = false;
  }

  void _onPageZoomChanged(bool isZoomed) => _isZoomed.value = isZoomed;

  // ── Swipe-to-dismiss ─────────────────────────────────────────────────────
  // _DismissOnlyDragRecognizer self-rejects when a second pointer appears,
  // so InteractiveViewer always wins the arena for pinch-to-zoom / pan.

  void _onDragUpdate(DragUpdateDetails d) {
    if (_isZoomed.value) return;
    if (d.delta.dy < 0 && _dragY == 0) return;
    setState(() {
      _dragY += d.delta.dy;
      if (_dragY < 0) _dragY = 0;
      _bgOpacity = (1.0 - (_dragY / 300.0)).clamp(0.3, 1.0);
    });
  }

  void _onDragEnd(DragEndDetails d) {
    if (_dragY > _dismissThreshold || d.velocity.pixelsPerSecond.dy > 600) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _dragY = 0;
        _bgOpacity = 1.0;
      });
    }
  }

  bool get _hasMultiple => widget.imageIds.length > 1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RawGestureDetector(
        gestures: {
          _DismissOnlyDragRecognizer:
              GestureRecognizerFactoryWithHandlers<_DismissOnlyDragRecognizer>(
            () => _DismissOnlyDragRecognizer(debugOwner: this),
            (instance) {
              instance
                ..onUpdate = _onDragUpdate
                ..onEnd = _onDragEnd;
            },
          ),
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          color: Colors.black.withValues(alpha: _bgOpacity),
          child: Transform.translate(
            offset: Offset(0, _dragY),
            child: Stack(
              children: [
                // ── Swipeable pages ───────────────────────────────────────
                ValueListenableBuilder<bool>(
                  valueListenable: _isZoomed,
                  builder: (_, isZoomed, __) => PageView.builder(
                    controller: _pageCtrl,
                    physics: _ZoomAwareScrollPhysics(
                      isZoomed: isZoomed,
                      parent: const PageScrollPhysics(),
                    ),
                    itemCount: widget.imageIds.length,
                    onPageChanged: (i) {
                      _resetZoom(_currentIndex);
                      setState(() => _currentIndex = i);
                      _isZoomed.value = false;
                      _decodeImageAt(i);
                      if (i + 1 < widget.imageIds.length) {
                        _decodeImageAt(i + 1);
                      }
                      if (i - 1 >= 0) {
                        _decodeImageAt(i - 1);
                      }
                    },
                    itemBuilder: (_, index) => _ImagePage(
                      imageId: widget.imageIds[index],
                      imageBytes: _imageBytes[index],
                      isLoading: _isDecoding[index],
                      transformCtrl: _transforms[index],
                      onZoomChanged: _onPageZoomChanged,
                      onTap: _toggleOverlay,
                    ),
                  ),
                ),

                // ── Overlay: top bar + dots ───────────────────────────────
                FadeTransition(
                  opacity: _overlayFade,
                  child: Stack(
                    children: [
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          child: Row(
                            children: [
                              _CircleButton(
                                  icon: Icons.close_rounded, onTap: _close),
                              const Spacer(),
                              if (_hasMultiple)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '${_currentIndex + 1} / ${widget.imageIds.length}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              const Spacer(),
                              const SizedBox(width: 40),
                            ],
                          ),
                        ),
                      ),
                      if (_hasMultiple && widget.imageIds.length <= 8)
                        Positioned(
                          bottom: 28,
                          left: 0,
                          right: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              widget.imageIds.length,
                              (i) => AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 3),
                                width: i == _currentIndex ? 18 : 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: i == _currentIndex
                                      ? Colors.white
                                      : Colors.white38,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Small helper ──────────────────────────────────────────────────────────────

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}
