import 'package:flutter/material.dart';

const double kFoldBreakpoint = 600.0;

class FoldLayoutData {
  final bool isUnfolded;
  final double width;
  final double height;

  const FoldLayoutData({
    required this.isUnfolded,
    required this.width,
    required this.height,
  });
}

class FoldLayout extends StatelessWidget {
  const FoldLayout({
    super.key,
    required this.compactBuilder,
    required this.expandedBuilder,
  });

  final Widget Function(BuildContext context, FoldLayoutData data)
      compactBuilder;
  final Widget Function(BuildContext context, FoldLayoutData data)
      expandedBuilder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final data = FoldLayoutData(
          isUnfolded: constraints.maxWidth >= kFoldBreakpoint,
          width: constraints.maxWidth,
          height: constraints.maxHeight,
        );

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          switchInCurve: Curves.easeInOutCubicEmphasized,
          switchOutCurve: Curves.easeInOutCubicEmphasized,
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: KeyedSubtree(
            key: ValueKey(data.isUnfolded),
            child: data.isUnfolded
                ? expandedBuilder(context, data)
                : compactBuilder(context, data),
          ),
        );
      },
    );
  }
}
