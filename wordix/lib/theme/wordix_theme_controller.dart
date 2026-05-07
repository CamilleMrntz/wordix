import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Persists [useClearLightTheme] on `users/{uid}` (`useClearLightTheme` bool).
class WordixThemeController extends ChangeNotifier {
  WordixThemeController() {
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_onAuthChanged);
  }

  late final StreamSubscription<User?> _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSub;

  bool _useClearLightTheme = false;
  bool get useClearLightTheme => _useClearLightTheme;

  void _onAuthChanged(User? user) {
    _userDocSub?.cancel();
    _userDocSub = null;
    if (user == null) {
      if (_useClearLightTheme) {
        _useClearLightTheme = false;
        notifyListeners();
      }
      return;
    }
    _userDocSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((snap) {
      final v = snap.data()?['useClearLightTheme'];
      final next = v is bool ? v : false;
      if (next != _useClearLightTheme) {
        _useClearLightTheme = next;
        notifyListeners();
      }
    });
  }

  Future<void> setUseClearLightTheme(bool value) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final previous = _useClearLightTheme;
    _useClearLightTheme = value;
    notifyListeners();
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {
          'useClearLightTheme': value,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {
      _useClearLightTheme = previous;
      notifyListeners();
      rethrow;
    }
  }

  @override
  void dispose() {
    _authSub.cancel();
    _userDocSub?.cancel();
    super.dispose();
  }
}

class WordixThemeBinding extends InheritedNotifier<WordixThemeController> {
  const WordixThemeBinding({
    super.key,
    required WordixThemeController controller,
    required super.child,
  }) : super(notifier: controller);

  static WordixThemeController of(BuildContext context) {
    final inherited = context.dependOnInheritedWidgetOfExactType<WordixThemeBinding>();
    assert(inherited != null, 'WordixThemeBinding not found');
    return inherited!.notifier!;
  }
}
