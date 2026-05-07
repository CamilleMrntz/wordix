import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Paramètres'),
      ),
      body: SafeArea(
        minimum: EdgeInsets.only(bottom: MediaQuery.viewPaddingOf(context).bottom + 16),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: scheme.primaryContainer.withValues(alpha: 0.65),
                          child: Icon(Icons.person_outline, color: scheme.primary, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Compte',
                          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.2),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.45)),
                    const SizedBox(height: 14),
                    Text(
                      'Adresse e-mail',
                      style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: SelectableText(
                          user?.email ?? 'Non disponible',
                          style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.home_outlined),
              label: const Text("Retour à l'accueil"),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: user == null
                  ? null
                  : () async {
                      await FirebaseAuth.instance.signOut();
                      if (!context.mounted) return;
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    },
              icon: const Icon(Icons.logout),
              label: const Text('Déconnexion'),
              style: FilledButton.styleFrom(
                foregroundColor: scheme.onError,
                backgroundColor: scheme.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
