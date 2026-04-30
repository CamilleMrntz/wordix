import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool isSaving = false;

  DocumentReference<Map<String, dynamic>> _prefsRef(String uid) {
    return FirebaseFirestore.instance.collection('user').doc(uid);
  }

  Future<void> _saveLanguage({
    required String uid,
    required String key,
    required bool value,
  }) async {
    setState(() => isSaving = true);
    try {
      await _prefsRef(uid).set({
        key: value,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      if (!mounted) return;
      setState(() => isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur sauvegarde: ${e.message ?? e.code}')),
      );
      return;
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Utilisateur non connecté')));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Accueil'),
        actions: [
          IconButton(
            onPressed: () => FirebaseAuth.instance.signOut(),
            icon: const Icon(Icons.logout),
          )
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _prefsRef(user.uid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data?.data() ?? <String, dynamic>{};
          final fr = data['fr'] == true;
          final en = data['en'] == true;
          final es = data['es'] == true;

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Connecté: ${user.email ?? "inconnu"}'),
                const SizedBox(height: 16),
                const Text('Langues actives'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilterChip(
                      label: const Text('Français'),
                      selected: fr,
                      onSelected: (value) =>
                          _saveLanguage(uid: user.uid, key: 'fr', value: value),
                    ),
                    FilterChip(
                      label: const Text('English'),
                      selected: en,
                      onSelected: (value) =>
                          _saveLanguage(uid: user.uid, key: 'en', value: value),
                    ),
                    FilterChip(
                      label: const Text('Español'),
                      selected: es,
                      onSelected: (value) =>
                          _saveLanguage(uid: user.uid, key: 'es', value: value),
                    ),
                  ],
                ),
                if (isSaving) ...[
                  const SizedBox(height: 12),
                  const Text('Sauvegarde...'),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}