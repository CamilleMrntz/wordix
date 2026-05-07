import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Daily local notification; preferences live on `users/{uid}`.
abstract final class DailyReminderService {
  static const int _notificationId = 91001;
  static const String _channelId = 'wordix_daily_reminder';

  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> ensureInitialized() async {
    if (kIsWeb) return;
    if (_initialized) return;
    tz_data.initializeTimeZones();
    final tzInfo = await FlutterTimezone.getLocalTimezone();
    try {
      tz.setLocalLocation(tz.getLocation(tzInfo.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(android: androidInit, iOS: darwinInit),
    );

    final androidImpl = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        'Rappel Wordix',
        description: 'Rappel quotidien pour le mot du jour',
        importance: Importance.defaultImportance,
      ),
    );
    _initialized = true;
  }

  /// Returns `true` if notifications can be shown (or user was already granted).
  static Future<bool> requestOsPermission() async {
    if (kIsWeb) return false;
    if (Platform.isAndroid) {
      final status = await Permission.notification.request();
      return status.isGranted;
    }
    if (Platform.isIOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      final ok = await ios?.requestPermissions(alert: true, badge: true, sound: true);
      return ok ?? false;
    }
    return true;
  }

  static Future<void> cancelScheduled() async {
    if (kIsWeb) return;
    await _plugin.cancel(id: _notificationId);
  }

  static Future<void> scheduleDaily({required int hour, required int minute}) async {
    if (kIsWeb) return;
    await ensureInitialized();
    await cancelScheduled();
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        'Rappel Wordix',
        channelDescription: 'Rappel quotidien pour le mot du jour',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: DarwinNotificationDetails(),
    );
    await _plugin.zonedSchedule(
      id: _notificationId,
      scheduledDate: scheduled,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: 'Wordix',
      body: 'Viens découvrir le mot du jour.',
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  /// Re-reads Firestore and applies schedule (e.g. after login or boot).
  static Future<void> syncFromRemote() async {
    if (kIsWeb) return;
    await ensureInitialized();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      await cancelScheduled();
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = doc.data();
      final enabled = data?['dailyReminderEnabled'] == true;
      final h = (data?['dailyReminderHour'] as num?)?.toInt() ?? 9;
      final m = (data?['dailyReminderMinute'] as num?)?.toInt() ?? 0;
      if (!enabled) {
        await cancelScheduled();
        return;
      }
      if (Platform.isAndroid) {
        final s = await Permission.notification.status;
        if (!s.isGranted) {
          await cancelScheduled();
          return;
        }
      }
      await scheduleDaily(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
    } on FirebaseException {
      await cancelScheduled();
    }
  }
}
