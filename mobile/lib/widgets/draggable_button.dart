import 'package:flutter/material.dart';

/// A draggable button that maintains its functionality while being movable.
class DraggableButton extends StatefulWidget {
  const DraggableButton({
    super.key,
    required this.initialPosition,
    required this.onPositionChanged,
    required this.child,
    required this.onTap,
    this.size = 48.0,
  });

  final Offset initialPosition;
  final ValueChanged<Offset> onPositionChanged;
  final Widget child;
  final VoidCallback onTap;
  final double size;

  @override
  State<DraggableButton> createState() => _DraggableButtonState();
}

class _DraggableButtonState extends State<DraggableButton> {
  late Offset _position;
  bool _isDragging = false;
  Offset? _dragStart;

  @override
  void initState() {
    super.initState();
    _position = widget.initialPosition;
  }

  @override
  void didUpdateWidget(DraggableButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialPosition != oldWidget.initialPosition && !_isDragging) {
      _position = widget.initialPosition;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        onPanStart: (details) {
          setState(() {
            _isDragging = true;
            _dragStart = details.globalPosition;
          });
        },
        onPanUpdate: (details) {
          setState(() {
            _position = Offset(
              (_position.dx + details.delta.dx).clamp(0.0,
                MediaQuery.of(context).size.width - widget.size),
              (_position.dy + details.delta.dy).clamp(0.0,
                MediaQuery.of(context).size.height - widget.size),
            );
          });
        },
        onPanEnd: (details) {
          // If drag distance is very small, treat as tap
          final totalDrag = _dragStart == null
              ? 0.0
              : (details.velocity.pixelsPerSecond.distance);

          setState(() {
            _isDragging = false;
          });

          // Save position after drag
          widget.onPositionChanged(_position);

          // If barely moved, trigger tap
          if (totalDrag < 50) {
            widget.onTap();
          }
        },
        onTap: () {
          if (!_isDragging) {
            widget.onTap();
          }
        },
        child: widget.child,
      ),
    );
  }
}
