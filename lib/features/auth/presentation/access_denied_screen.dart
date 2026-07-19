import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AccessDeniedScreen extends StatelessWidget {
  const AccessDeniedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.admin_panel_settings_outlined,
                    size: 64,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Access denied',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Your FixNow role does not have permission to open this page.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => context.go('/login'),
                    icon: const Icon(Icons.home_outlined),
                    label: const Text('Return to dashboard'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
