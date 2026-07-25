import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/button_positions.dart';

/// A draggable button that saves its position via ButtonPositions service.
class DraggableButton extends StatefulWidget {
  const DraggableButton({
    super.key,
    required this.buttonKey,
    required this.defaultPosition,
    required this.child,
    this.size = 48.0,
  });

  final String buttonKey;
  final Offset defaultPosition;
  final Widget child;
  final double size;

  @override
  State<DraggableButton> createState() => _DraggableButtonState();
}

class _DraggableButtonState extends State<DraggableButton> {
  Offset? _position;
  bool _isDragging = false;
  Offset? _dragStart;

  Offset _getPosition(ButtonPositions positions) {
    if (_position != null) return _position!;
    switch (widget.buttonKey) {
      case 'fullscreen':
        return positions.fullscreenPos;
      case 'settings':
        return positions.settingsPos;
      case 'mute':
        return positions.volumePos;
      case 'fastforward':
        return positions.fastForwardPos;
      default:
        return widget.defaultPosition;
    }
  }

  Future<void> _savePosition(BuildContext context, Offset pos) async {
    final positions = context.read<ButtonPositions>();
    switch (widget.buttonKey) {
      case 'fullscreen':
        await positions.setFullscreenPos(pos);
        break;
      case 'settings':
        await positions.setSettingsPos(pos);
        break;
      case 'mute':
        await positions.setVolumePos(pos);
        break;
      case 'fastforward':
        await positions.setFastForwardPos(pos);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ButtonPositions>(
      builder: (context, positions, _) {
        final position = _getPosition(positions);
        return Positioned(
          left: position.dx,
          top: position.dy,
          child: GestureDetector(
            onPanStart: (details) {
              setState(() {
                _isDragging = true;
                _dragStart = position;
              });
            },
            onPanUpdate: (details) {
              setState(() {
                _position = Offset(
                  ((_position ?? position).dx + details.delta.dx).clamp(
                    0.0,
                    MediaQuery.of(context).size.width - widget.size,
                  ),
                  ((_position ?? position).dy + details.delta.dy).clamp(
                    0.0,
                    MediaQuery.of(context).size.height - widget.size,
                  ),
                );
              });
            },
            onPanEnd: (details) {
              final moved = _dragStart != null && _position != null
                  ? (_position!.dx - _dragStart!.dx).abs() +
                      (_position!.dy - _dragStart!.dy).abs()
                  : 0.0;

              if (_position != null) {
                _savePosition(context, _position!);
              }

              setState(() {
                _isDragging = false;
                _dragStart = null;
              });

              // If barely moved, it was a tap - let child handle it
              if (moved < 10) {
                // Child widgets have their own onPressed handlers
              }
            },
            child: widget.child,
          ),
        );
      },
    );
  }
}
