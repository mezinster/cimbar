import 'dart:math' as math;

import 'package:flutter/material.dart';

/// SPIKE: tablet-width layout helpers.
///
/// Wide = the window is at least 840 pt across and its shorter side at least
/// 600 pt: iPads (not in a narrow Split View), Android tablets and unfolded
/// foldables. No iPhone qualifies, even on its side (shorter side ~440 pt).
bool isWide(BuildContext context) {
  final s = MediaQuery.sizeOf(context);
  return s.width >= 840 && s.shortestSide >= 600;
}

/// Two scrolling panes side by side: [left] is the form, [right] the result
/// or preview. On a narrow window the caller keeps its one-column ListView.
class TwoPane extends StatelessWidget {
  final List<Widget> left;
  final Widget right;

  const TwoPane({super.key, required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    // 440 pt for the form, but never more than 45% of the body, so at the
    // narrowest wide windows (foldables, ~840 pt) the result pane stays at
    // least as wide as the form.
    return LayoutBuilder(builder: (context, constraints) => Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: math.min(440, constraints.maxWidth * 0.45),
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(24, 16, 12, 24),
            children: left,
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 24, 24),
            child: right,
          ),
        ),
      ],
    ));
  }
}

/// The right pane before there is anything to show.
class EmptyPane extends StatelessWidget {
  final IconData icon;
  final String text;

  const EmptyPane({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text(text, style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.outline)),
        ]),
      ),
    );
  }
}

/// A single column centred at a readable width (About, Files).
class CentredColumn extends StatelessWidget {
  final Widget child;
  const CentredColumn({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!isWide(context)) return child;
    return Center(
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 680), child: child),
    );
  }
}

/// The screen body: [children] in one scrolling column on a narrow window, or
/// as the left pane next to [right] on a wide one.
Widget adaptiveBody(BuildContext context, {required Widget right, required List<Widget> children}) {
  if (isWide(context)) return TwoPane(left: children, right: right);
  return ListView(
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    padding: const EdgeInsets.all(16),
    children: children,
  );
}
