import 'package:flutter/material.dart';
import 'dart:math' as math;

/// 扇形展开的 FAB 菜单项
class SpeedDialAction {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool enabled;
  final String? disabledTooltip;

  const SpeedDialAction({
    required this.icon,
    required this.label,
    this.onTap,
    this.enabled = true,
    this.disabledTooltip,
  });
}

/// 扇形展开的 FAB
class SpeedDialFAB extends StatefulWidget {
  final List<SpeedDialAction> actions;
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback? onPressed;

  const SpeedDialFAB({
    super.key,
    required this.actions,
    this.icon = Icons.add,
    required this.backgroundColor,
    this.foregroundColor = Colors.white,
    this.onPressed,
  });

  @override
  State<SpeedDialFAB> createState() => _SpeedDialFABState();
}

class _SpeedDialFABState extends State<SpeedDialFAB>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _expandAnimation;
  bool _isOpen = false;
  int? _hoveredIndex; // 当前悬停的按钮索引

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onLongPressStart(LongPressStartDetails details) {
    setState(() {
      _isOpen = true;
      _controller.forward();
    });
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    setState(() {
      _updateHoveredIndex(details.localPosition);
    });
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    // 触发悬停按钮的动作
    if (_hoveredIndex != null && _hoveredIndex! < widget.actions.length) {
      final action = widget.actions[_hoveredIndex!];
      if (action.onTap != null) {
        action.onTap!();
      }
    }

    // 关闭菜单
    setState(() {
      _isOpen = false;
      _hoveredIndex = null;
      _controller.reverse();
    });
  }

  void _updateHoveredIndex(Offset position) {
    // 计算每个按钮的位置并检查是否悬停
    final angles = [210.0, 270.0, 330.0];
    const distance = 75.0;
    const buttonRadius = 28.0; // 按钮半径

    // 在250x250容器中：
    // - FAB位于bottom=0，尺寸80x80
    // - FAB底部在y=250，顶部在y=170，中心在y=210
    // - FAB水平居中，left=85，中心x=125

    // GestureDetector的top-left在(85, 170)
    const fabLeft = 85.0;
    const fabTop = 170.0;

    // 将拖动位置从GestureDetector坐标系(80x80)转换到250x250容器坐标系
    final transformedX = position.dx + fabLeft;
    final transformedY = position.dy + fabTop;

    int? newHoveredIndex;
    for (int i = 0; i < widget.actions.length && i < angles.length; i++) {
      final angle = angles[i];
      final radians = angle * math.pi / 180;
      final offsetX = distance * math.cos(radians);
      final offsetY = distance * math.sin(radians);

      // 按钮通过Positioned定位：bottom = 40 - offsetY, left = 97 + offsetX
      // 按钮尺寸56x56，所以中心偏移28
      final buttonBottom = 40.0 - offsetY;
      final buttonLeft = 97.0 + offsetX; // 125 - 28

      // 转换到容器坐标系(从顶部算)
      final buttonCenterX = buttonLeft + 28.0;
      final buttonCenterY = 250.0 - buttonBottom - 28.0;

      // 计算距离
      final dx = transformedX - buttonCenterX;
      final dy = transformedY - buttonCenterY;
      final distanceToButton = math.sqrt(dx * dx + dy * dy);

      if (distanceToButton <= buttonRadius) {
        newHoveredIndex = i;
        break;
      }
    }

    if (newHoveredIndex != _hoveredIndex) {
      setState(() {
        _hoveredIndex = newHoveredIndex;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      height: 80,
      child: OverflowBox(
        minWidth: 0,
        maxWidth: 250,
        minHeight: 0,
        maxHeight: 250,
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: 250,
          height: 250,
          child: Stack(
            alignment: Alignment.bottomCenter,
            clipBehavior: Clip.none,
            children: [
          // 主 FAB（先渲染，在下层）
          Positioned(
            bottom: 0,
            child: GestureDetector(
              onLongPressStart: _onLongPressStart,
              onLongPressMoveUpdate: _onLongPressMoveUpdate,
              onLongPressEnd: _onLongPressEnd,
              child: SizedBox(
                width: 80,
                height: 80,
                child: FloatingActionButton(
                  heroTag: 'mainFab',
                  elevation: 8,
                  shape: const CircleBorder(),
                  backgroundColor: widget.backgroundColor,
                  onPressed: widget.onPressed,
                  child: AnimatedBuilder(
                    animation: _expandAnimation,
                    builder: (context, child) {
                      return Transform.rotate(
                        angle: _expandAnimation.value * math.pi / 4,
                        child: Icon(
                          _isOpen ? Icons.close : widget.icon,
                          color: widget.foregroundColor,
                          size: 34,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),

          // 扇形展开的子按钮（后渲染，在上层）
          ..._buildSpeedDialActions(),
        ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSpeedDialActions() {
    final List<Widget> children = [];

    // 固定角度：拍照(左上210°)、相册(正上270°)、语音(右上330°)
    final List<double> angles = [210.0, 270.0, 330.0];

    for (int i = 0; i < widget.actions.length && i < angles.length; i++) {
      final action = widget.actions[i];
      final double angle = angles[i];
      final double radians = angle * math.pi / 180;

      // 距离主 FAB 中心的半径
      final double distance = 75;

      children.add(
        AnimatedBuilder(
          animation: _expandAnimation,
          builder: (context, child) {
            if (_expandAnimation.value == 0) {
              return const SizedBox.shrink();
            }

            final double progress = _expandAnimation.value;
            final double offsetX = progress * distance * math.cos(radians);
            final double offsetY = progress * distance * math.sin(radians);

            // FAB 中心在容器的 (125, 40) 位置
            // 子按钮宽度56，所以中心偏移量是 56/2 = 28
            return Positioned(
              bottom: 40 - offsetY, // Y轴向下为正，向上为负
              left: 125 - 28 + offsetX, // 从 FAB 中心出发
              child: Transform.scale(
                scale: progress,
                child: Opacity(
                  opacity: progress,
                  child: child,
                ),
              ),
            );
          },
          child: _SpeedDialButton(
            action: action,
            isHovered: i == _hoveredIndex,
          ),
        ),
      );
    }

    return children;
  }
}

/// 扇形展开的单个按钮
class _SpeedDialButton extends StatelessWidget {
  final SpeedDialAction action;
  final bool isHovered;

  const _SpeedDialButton({
    required this.action,
    required this.isHovered,
  });

  @override
  Widget build(BuildContext context) {
    final bool isEnabled = action.enabled;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final Color bgColor = isEnabled
        ? primaryColor
        : Colors.grey.shade400;

    return AnimatedScale(
      scale: isHovered ? 1.2 : 1.0,
      duration: const Duration(milliseconds: 150),
      child: Material(
        color: bgColor,
        shape: const CircleBorder(),
        elevation: isHovered ? 8 : 4,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: isHovered
                ? Border.all(color: Colors.white, width: 3)
                : null,
          ),
          child: Icon(
            action.icon,
            color: Colors.white,
            size: 28,
          ),
        ),
      ),
    );
  }
}
