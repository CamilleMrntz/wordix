import 'package:flutter/material.dart';

/// Wordix wordmark: monogram + logotype (vector, scales with [height]).
class WordixLogo extends StatelessWidget {
  const WordixLogo({super.key, this.height = 30});

  /// Total height of the logo (AppBar-friendly ~28–32).
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final markSize = height * 0.92;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: markSize,
          height: markSize,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(height * 0.22),
            border: Border.all(color: scheme.outline.withValues(alpha: 0.14), width: 1),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                scheme.primary,
                Color.lerp(scheme.primary, scheme.tertiary, 0.35)!,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: scheme.primary.withValues(alpha: 0.22),
                blurRadius: 8,
                offset: const Offset(0, 3),
                spreadRadius: -1,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            'W',
            style: TextStyle(
              color: scheme.onPrimary,
              fontWeight: FontWeight.w900,
              fontSize: markSize * 0.52,
              height: 1,
              letterSpacing: -1,
            ),
          ),
        ),
        SizedBox(width: height * 0.2),
        Text.rich(
          TextSpan(
            style: textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.9,
              fontSize: height * 0.68,
              height: 1,
              color: scheme.onSurface,
            ),
            children: [
              TextSpan(
                text: 'Word',
                style: TextStyle(color: scheme.primary),
              ),
              const TextSpan(text: 'ix'),
            ],
          ),
        ),
      ],
    );
  }
}
