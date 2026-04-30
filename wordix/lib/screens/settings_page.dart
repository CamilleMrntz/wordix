import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Paramètres'),
      ),
      body: SafeArea(
        minimum: const EdgeInsets.only(bottom: 28),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Compte',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Adresse e-mail',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 4),
              SelectableText(
                user?.email ?? 'Non disponible',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const Spacer(),
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
                  foregroundColor: Theme.of(context).colorScheme.onError,
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
