import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  static const String _channelId = 'gg_kasir_connectivity';
  static const String _channelName = 'GG Kasir Connectivity';
  static bool _permissionGranted = false;

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool get permissionGranted => _permissionGranted;

  /// Initializes the [FlutterLocalNotificationsPlugin] and creates the
  /// Android notification channel, then requests permission.
  static Future<void> init() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initSettings =
        InitializationSettings(android: androidSettings);

    await _plugin.initialize(initSettings);

    // Create the Android notification channel with high importance.
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      importance: Importance.high,
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await requestPermission();
  }

  /// Checks whether permission has been asked before via [SharedPreferences].
  /// If not, shows a rationale and then requests via [permission_handler].
  /// Stores the result and returns whether permission was granted.
  static Future<bool> requestPermission() async {
    final prefs = await SharedPreferences.getInstance();
    final alreadyAsked = prefs.getBool('notif_permission_asked') ?? false;

    if (!alreadyAsked) {
      await prefs.setBool('notif_permission_asked', true);

      final status = await Permission.notification.request();
      _permissionGranted = status.isGranted;
    } else {
      // Permission was asked before — check current status without prompting.
      final status = await Permission.notification.status;
      _permissionGranted = status.isGranted;
    }

    return _permissionGranted;
  }

  /// Shows a local notification indicating the device is offline.
  /// No-op if [_permissionGranted] is `false`.
  static Future<void> showOfflineNotification() async {
    if (!_permissionGranted) return;

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      _channelId,
      _channelName,
      importance: Importance.high,
      priority: Priority.high,
    );

    const NotificationDetails details =
        NotificationDetails(android: androidDetails);

    await _plugin.show(
      1001,
      'Kamu Offline',
      'Transaksi akan disimpan lokal',
      details,
    );
  }

  /// Shows a local notification indicating the device is back online.
  /// No-op if [_permissionGranted] is `false`.
  static Future<void> showOnlineNotification() async {
    if (!_permissionGranted) return;

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      _channelId,
      _channelName,
      importance: Importance.high,
      priority: Priority.high,
    );

    const NotificationDetails details =
        NotificationDetails(android: androidDetails);

    await _plugin.show(
      1002,
      'Kembali Online',
      'Transaksi offline sedang disinkronkan',
      details,
    );
  }
}
