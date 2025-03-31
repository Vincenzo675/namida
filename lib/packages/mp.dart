import 'dart:async';

import 'package:flutter/material.dart';

import 'package:namida/controller/scroll_search_controller.dart';
import 'package:namida/controller/wakelock_controller.dart';
import 'package:namida/core/extensions.dart';
import 'package:namida/core/utils.dart';
import 'package:namida/ui/widgets/custom_widgets.dart';

/// Used to retain state for cases like navigating after pip mode.
bool _wasExpanded = false;

/// this exists as a workaround for using pip widget height instead of device real height.
/// using split screen might make this buggy.
///
/// another possible workaround is to wait until activity gets resized, but we dont know exact numbers.
double _maxHeight = 0;

class NamidaYTMiniplayer extends StatefulWidget {
  final bool enforceExpanded;
  final double minHeight, maxHeight, bottomMargin;
  final Widget Function(double height, double percentage) builder;
  final Color bgColor;
  final void Function(double percentage)? onHeightChange;
  final void Function(double dismissPercentage)? onDismissing;
  final Duration duration;
  final Curve curve;
  final void Function()? onDismiss;
  final bool displayBottomBGLayer;
  final void Function()? onAlternativePercentageExecute;

  const NamidaYTMiniplayer({
    super.key,
    this.enforceExpanded = false,
    required this.minHeight,
    required this.maxHeight,
    required this.builder,
    required this.bgColor,
    this.onHeightChange,
    this.onDismissing,
    this.bottomMargin = 0.0,
    this.duration = const Duration(milliseconds: 300),
    this.curve = Curves.decelerate,
    this.onDismiss,
    this.displayBottomBGLayer = false,
    this.onAlternativePercentageExecute,
  });

  @override
  State<NamidaYTMiniplayer> createState() => NamidaYTMiniplayerState();
}

class NamidaYTMiniplayerState extends State<NamidaYTMiniplayer> with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    final startExpanded = widget.enforceExpanded || _wasExpanded;
    if (_maxHeight < maxHeight) _maxHeight = maxHeight;

    controller = AnimationController(
      vsync: this,
      duration: Duration.zero,
      lowerBound: 0,
      upperBound: 1,
      value: startExpanded ? 1.0 : widget.minHeight / _maxHeight,
    );

    if (widget.onHeightChange != null) {
      _listenerHeightChange();
      controller.addListener(_listenerHeightChange);
    }
    if (widget.onDismissing != null) {
      controller.addListener(_listenerDismissing);
    }

    _dragheight = startExpanded ? _maxHeight : widget.minHeight;

    WakelockController.inst.updateMiniplayerStatus(startExpanded);

    _ensureCorrectInitializedPadding();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _ensureCorrectInitializedPadding() async {
    await Future.delayed(Duration.zero);

    for (int i = 0; i < 10; i++) {
      if (!mounted) break;
      // -- context access in build makes it awful for yt miniplayer (since it has MaterialPage),
      // -- the keyboard keeps showing/hiding
      // -- so yeah we only check once
      final padding = MediaQuery.paddingOf(context);
      if (_padding != padding) {
        if (padding.bottom > _padding.bottom) {
          // bottom only bcz.. well..
          _padding = padding;
          animateToState(_wasExpanded);
          break;
        } else {
          _padding = padding;
        }
      }

      await Future.delayed(Duration(milliseconds: 800));
    }
  }

  void _listenerHeightChange() {
    widget.onHeightChange!(percentage);
  }

  void _listenerDismissing() {
    if (controllerHeight <= widget.minHeight) {
      widget.onDismissing!(dismissPercentage);
    }
  }

  /// used to invoke other animation (eg. entering video fullscreen),
  bool _alternativePercentage = false;
  bool _isDraggingDownwards = false;
  double get _percentageMultiplier => _alternativePercentage && _isDraggingDownwards ? 0.25 : 1.0;

  bool _isDragManagedInternally = true;

  void setDragExternally(bool external) {
    _alternativePercentage = external;
    _isDragManagedInternally = !external;
  }

  void saveDragHeightStart() {
    _startedDragAtHeight = _dragheight;
  }

  double? _startedDragAtHeight;

  bool get isExpanded => _dragheight >= maxHeight - widget.minHeight;
  bool get _dismissible => widget.onDismiss != null;

  double _dragheight = 0;

  EdgeInsets _padding = EdgeInsets.zero;

  double get maxHeight => widget.maxHeight - _padding.bottom - _padding.top;
  double get controllerHeight => controller.value * maxHeight;
  double get percentage => (controllerHeight - widget.minHeight) / (maxHeight - widget.minHeight);
  double get dismissPercentage => (controllerHeight / widget.minHeight).clamp(0.0, 1.0);

  void _updateHeight(double heightPre, {Duration? duration}) {
    final height = _dismissible ? heightPre : heightPre.withMinimum(widget.minHeight);
    controller.animateTo(
      height / maxHeight,
      duration: duration,
      curve: widget.curve,
    );
    _dragheight = height;
  }

  void animateToState(bool toExpanded, {Duration? dur, bool dismiss = false}) {
    if (widget.enforceExpanded) {
      toExpanded = true;
      dismiss = false;
    }

    if (dismiss) {
      _updateHeight(0, duration: dur ?? widget.duration);
      WakelockController.inst.updateMiniplayerStatus(false);
      return;
    }

    _updateHeight(toExpanded ? maxHeight : widget.minHeight, duration: dur ?? widget.duration);
    _wasExpanded = toExpanded;
    WakelockController.inst.updateMiniplayerStatus(toExpanded);

    if (toExpanded) {
      ScrollSearchController.inst.unfocusKeyboard();
    }
  }

  void onVerticalDragUpdate(double dy) {
    _isDraggingDownwards = dy > 0;
    if (_isDraggingDownwards && widget.enforceExpanded) return;
    _dragheight -= dy * _percentageMultiplier;
    _updateHeight(_dragheight, duration: Duration.zero);
  }

  void _resetValues() {
    _alternativePercentage = false;
    _startedDragAtHeight = null;
  }

  void onVerticalDragEnd(double v) {
    if (!_alternativePercentage && widget.onDismiss != null && ((v > 200 && _dragheight <= widget.minHeight * 0.9) || _dragheight <= widget.minHeight * 0.65)) {
      animateToState(false, dismiss: true);
      widget.onDismiss!();
      _resetValues();
      return;
    }

    bool shouldSnapToMax = false;
    if (v > 200) {
      shouldSnapToMax = false;
    } else if (v < -200) {
      shouldSnapToMax = true;
    } else {
      final percentage = _dragheight / maxHeight * _percentageMultiplier;
      if (percentage > 0.4) {
        shouldSnapToMax = true;
      } else {
        shouldSnapToMax = false;
      }
    }

    if (shouldSnapToMax) {
      animateToState(true);
    } else {
      if (_alternativePercentage) {
        final didDragDownwards = _startedDragAtHeight != null && _startedDragAtHeight! > _dragheight;
        if (didDragDownwards) widget.onAlternativePercentageExecute?.call();
        animateToState(_wasExpanded);
      } else {
        animateToState(false);
      }
    }
    _resetValues();
  }

  @override
  Widget build(BuildContext context) {
    final maxWidth = context.width;
    return AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final percentage = this.percentage;
          final totalBottomPadding = _padding.bottom + (widget.bottomMargin * (1.0 - percentage)).clamp(0, widget.bottomMargin);
          return RepaintBoundary(
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                if (widget.displayBottomBGLayer)
                  SizedBox(
                    height: totalBottomPadding,
                    width: maxWidth,
                    child: ColoredBox(color: widget.bgColor),
                  ),
                Padding(
                  padding: EdgeInsets.only(
                    top: _padding.top,
                    bottom: totalBottomPadding,
                  ),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: GestureDetector(
                      onTap: _dragheight == widget.minHeight ? () => animateToState(true) : null,
                      onVerticalDragUpdate: (details) => onVerticalDragUpdate(details.delta.dy),
                      onVerticalDragEnd: (details) {
                        if (_isDragManagedInternally) onVerticalDragEnd(details.velocity.pixelsPerSecond.dy);
                      },
                      child: Material(
                        clipBehavior: Clip.hardEdge,
                        type: MaterialType.transparency,
                        child: NamidaOpacity(
                          enabled: controllerHeight < widget.minHeight,
                          opacity: dismissPercentage,
                          child: RepaintBoundary(
                            child: SizedBox(
                              height: controllerHeight,
                              child: ColoredBox(
                                color: widget.bgColor,
                                child: widget.builder(controllerHeight, percentage),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        });
  }
}
