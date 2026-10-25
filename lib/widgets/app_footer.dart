import 'package:flutter/material.dart';

class AppFooter extends StatelessWidget {
  const AppFooter({super.key});

  static const notice =
      '© 2026 Barath M · All rights reserved · Chennai, Tamil Nadu, India';

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    bottom: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Text(
        notice,
        textAlign: TextAlign.center,
        softWrap: true,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 12,
        ),
      ),
    ),
  );
}
