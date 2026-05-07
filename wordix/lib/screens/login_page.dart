import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../widgets/wordix_logo.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  String? error;
  bool isLoading = false;

  Future<void> signIn() async {
    setState(() {
      error = null;
      isLoading = true;
    });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailCtrl.text.trim(),
        password: passCtrl.text.trim(),
      );
    } on FirebaseAuthException catch (e) {
      setState(() => error = e.message);
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> signUp() async {
    setState(() {
      error = null;
      isLoading = true;
    });
    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: emailCtrl.text.trim(),
        password: passCtrl.text.trim(),
      );
    } on FirebaseAuthException catch (e) {
      setState(() => error = e.message);
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> signInWithGoogle() async {
    setState(() {
      error = null;
      isLoading = true;
    });
    try {
      if (kIsWeb) {
        final provider = GoogleAuthProvider();
        await FirebaseAuth.instance.signInWithPopup(provider);
        return;
      }

      await GoogleSignIn.instance.initialize(
        serverClientId:
            '823537100827-8j8jsarboqi9223sr8d8rb478jh4ui3i.apps.googleusercontent.com',
      );
      final googleUser = await GoogleSignIn.instance.authenticate();
      final googleAuth = googleUser.authentication;
      if (googleAuth.idToken == null) {
        throw Exception('Google idToken missing');
      }
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      setState(() => error = e.message ?? 'Erreur Firebase Auth.');
    } catch (e) {
      setState(() => error = 'Erreur Google: $e');
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connexion'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(child: WordixLogo(height: 36)),
                      const SizedBox(height: 14),
                      Text(
                        'Connecte-toi pour suivre ton mot du jour.',
                        textAlign: TextAlign.center,
                        style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.35),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(labelText: 'E-mail'),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: passCtrl,
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) {
                          if (!isLoading) signIn();
                        },
                        decoration: const InputDecoration(labelText: 'Mot de passe'),
                      ),
                      const SizedBox(height: 22),
                      FilledButton(
                        onPressed: isLoading ? null : signIn,
                        child: const Text('Se connecter'),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: isLoading ? null : signUp,
                        child: const Text('Créer un compte'),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(child: Divider(color: scheme.outlineVariant.withValues(alpha: 0.6))),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text('ou', style: textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
                          ),
                          Expanded(child: Divider(color: scheme.outlineVariant.withValues(alpha: 0.6))),
                        ],
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: isLoading ? null : signInWithGoogle,
                        icon: const Icon(Icons.login),
                        label: const Text('Continuer avec Google'),
                      ),
                      if (isLoading) ...[
                        const SizedBox(height: 20),
                        const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
                      ],
                      if (error != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: scheme.errorContainer,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: scheme.error.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.error_outline, size: 20, color: scheme.onErrorContainer),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  error!,
                                  style: textTheme.bodySmall?.copyWith(
                                    color: scheme.onErrorContainer,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
