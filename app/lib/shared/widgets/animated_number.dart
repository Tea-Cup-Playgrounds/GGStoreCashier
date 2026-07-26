import 'package:flutter/material.dart';

/// Animates between two text values whenever [value] changes.
///
/// - Pure text values (non-numeric like "Rp 1,2 jt") use a fast
///   vertical slide + fade transition.
/// - Plain integer strings get a smooth CountUp roll from old → new.
class AnimatedNumber extends StatefulWidget {
  final String value;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  const AnimatedNumber({
    super.key,
    required this.value,
    this.style,
    this.maxLines,
    this.overflow,
  });

  @override
  State<AnimatedNumber> createState() => _AnimatedNumberState();
}

class _AnimatedNumberState extends State<AnimatedNumber> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fadeIn;
  late Animation<Offset> _slideIn;
  late Animation<Offset> _slideOut;

  String _displayed = '';
  String _next = '';

  @override
  void initState() {
    super.initState();
    _displayed = widget.value;
    _next = widget.value;

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );

    _fadeIn = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _slideIn = Tween<Offset>(
      begin: const Offset(0, 0.35),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _slideOut = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, -0.35),
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInCubic));
  }

  @override
  void didUpdateWidget(AnimatedNumber oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _next = widget.value;
      _ctrl.forward(from: 0).then((_) {
        if (mounted) setState(() => _displayed = _next);
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final isAnimating = _ctrl.isAnimating;

        return Stack(
          alignment: Alignment.centerLeft,
          children: [
            // Old value — slides out upward
            if (isAnimating)
              SlideTransition(
                position: _slideOut,
                child: Opacity(
                  opacity: 1 - _fadeIn.value,
                  child: Text(
                    _displayed,
                    style: widget.style,
                    maxLines: widget.maxLines,
                    overflow: widget.overflow ?? TextOverflow.ellipsis,
                  ),
                ),
              ),

            // New value — slides in from below
            SlideTransition(
              position: _slideIn,
              child: FadeTransition(
                opacity: isAnimating ? _fadeIn : const AlwaysStoppedAnimation(1),
                child: Text(
                  isAnimating ? _next : _displayed,
                  style: widget.style,
                  maxLines: widget.maxLines,
                  overflow: widget.overflow ?? TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
