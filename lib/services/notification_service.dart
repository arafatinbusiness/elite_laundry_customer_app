import 'dart:typed_data';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../main.dart'; // Import main to access navigatorKey

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Notification sounds for different order events
  static const String _defaultSound = 'newmusic';     // Use the MP3 file (newmusic.mp3)
  static const String _arrivalSound = 'mixkit';       // Use the WAV file (mixkit.wav)
  static const String _deliverySound = 'mixkit';      // Use same sound for delivery
  static const String _paymentSound = 'newmusic';     // Use the MP3 file (newmusic.mp3)
  static const String _confirmationSound = 'newmusic'; // Use the MP3 file (newmusic.mp3)

  Future<void> initialize() async {
    const AndroidInitializationSettings androidInitializationSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosInitializationSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: androidInitializationSettings,
      iOS: iosInitializationSettings,
    );

    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        _handleNotificationClick(response.payload);
      },
    );

    // Create notification channel for Android (required for custom sounds)
    await _createNotificationChannel();

    // Request permissions
    await _requestPermissions();
  }

  Future<void> _createNotificationChannel() async {
    final AndroidNotificationChannel channel = AndroidNotificationChannel(
      'order_channel', // id
      'Order Notifications', // title
      description: 'Notifications for order status updates',
      importance: Importance.high,
      playSound: true,
      // Don't set a default sound here - let individual notifications specify their own sounds
      // This allows different notification types to have different custom sounds
    );

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
    
    print('✅ DEBUG: Notification channel created successfully (no default sound set)');
  }

  Future<void> _requestPermissions() async {
    // For Android, permissions are handled in AndroidManifest.xml
    // For iOS, we'll use a simpler approach - the plugin handles permissions automatically
    // when we initialize with DarwinInitializationSettings
  }

  Future<void> showOrderNotification({
    required String title,
    required String body,
    required String orderId,
    required String branchId,
    required String notificationType,
    bool playSound = true,
  }) async {
    final String soundFile = _getSoundForType(notificationType);
    final String soundExtension = soundFile == 'mixkit' ? '.wav' : '.mp3';
    
    print('🔔 DEBUG: Showing order notification - Type: $notificationType, Order: $orderId');
    print('🔔 DEBUG: Title: "$title", Body: "$body"');
    print('🔔 DEBUG: Sound enabled: $playSound');
    print('🔔 DEBUG: Selected sound file: $soundFile$soundExtension');
    print('🔔 DEBUG: Sound resource path: res/raw/$soundFile$soundExtension');

    final AndroidNotificationDetails androidNotificationDetails =
        AndroidNotificationDetails(
      'order_channel',
      'Order Notifications',
      channelDescription: 'Notifications for order status updates',
      importance: Importance.high,
      priority: Priority.high,
      playSound: playSound,
      // Use custom sound files from res/raw directory
      sound: RawResourceAndroidNotificationSound(soundFile),
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 500, 1000, 500]),
      autoCancel: true,
      showWhen: true,
    );

    final DarwinNotificationDetails iosNotificationDetails =
        DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: playSound,
      sound: soundFile,
    );

    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidNotificationDetails,
      iOS: iosNotificationDetails,
    );

    // Generate a unique ID for each notification to avoid stacking
    final int notificationId = DateTime.now().millisecondsSinceEpoch.remainder(100000);

    print('🔔 DEBUG: Attempting to show notification with ID: $notificationId');
    print('🔔 DEBUG: Notification details: $notificationDetails');

    try {
      await _notificationsPlugin.show(
        notificationId,
        title,
        body,
        notificationDetails,
        payload: 'order:$orderId:$branchId:$notificationType',
      );
      print('✅ DEBUG: Notification displayed successfully - ID: $notificationId');
      print('✅ DEBUG: Sound should be playing: $soundFile$soundExtension');
    } catch (e) {
      print('❌ DEBUG: Failed to show notification: $e');
      print('❌ DEBUG: Error details: ${e.toString()}');
      
      // Check if it's a sound-related error
      if (e.toString().contains('sound') || e.toString().contains('audio')) {
        print('❌ DEBUG: Sound-related error detected');
        print('❌ DEBUG: Please check if sound file $soundFile$soundExtension exists in android/app/src/main/res/raw/');
      }
    }
  }

  static String _getSoundForType(String notificationType) {
    String sound;
    switch (notificationType) {
      case 'driver_arrived':
        sound = _arrivalSound;
        break;
      case 'delivery_arrived':
        sound = _deliverySound;
        break;
      case 'payment_required':
        sound = _paymentSound;
        break;
      case 'order_confirmed':
        sound = _confirmationSound;
        break;
      case 'order_completed':
        sound = _confirmationSound;
        break;
      default:
        sound = _defaultSound;
    }
    print('🔊 DEBUG: Selected sound for type "$notificationType": $sound');
    return sound;
  }

  void _handleNotificationClick(String? payload) {
    if (payload == null || !payload.startsWith('order:')) return;

    final parts = payload.split(':');
    if (parts.length >= 3) {
      final String orderId = parts[1];
      final String branchId = parts[2];
      final String notificationType = parts.length > 3 ? parts[3] : '';

      // Navigate to order tracking screen
      _navigateToOrderTracking(orderId, branchId, notificationType);
    }
  }

  void _navigateToOrderTracking(String orderId, String branchId, String notificationType) {
    // Navigate to the order tracking screen using the global navigatorKey
    navigatorKey.currentState?.pushNamed(
      '/order-tracking',
      arguments: {
        'orderId': orderId,
        'branchId': branchId,
      },
    );
  }

  // Specific notification methods for different order events
  Future<void> showDriverArrivedNotification({
    required String orderId,
    required String branchId,
    required String driverName,
  }) async {
    await showOrderNotification(
      title: '🚗 Driver Has Arrived!',
      body: '$driverName is at your location to collect your laundry',
      orderId: orderId,
      branchId: branchId,
      notificationType: 'driver_arrived',
      playSound: true,
    );
  }

  Future<void> showDeliveryArrivedNotification({
    required String orderId,
    required String branchId,
    required String driverName,
    required double amount,
  }) async {
    await showOrderNotification(
      title: '📦 Delivery Arrived!',
      body: '$driverName is here with your clean clothes. Amount: \$$amount',
      orderId: orderId,
      branchId: branchId,
      notificationType: 'delivery_arrived',
      playSound: true,
    );
  }

  Future<void> showOrderConfirmedNotification({
    required String orderId,
    required String branchId,
  }) async {
    await showOrderNotification(
      title: '✅ Order Confirmed',
      body: 'Your laundry order has been confirmed by the driver',
      orderId: orderId,
      branchId: branchId,
      notificationType: 'order_confirmed',
      playSound: true,
    );
  }

  Future<void> showPaymentRequiredNotification({
    required String orderId,
    required String branchId,
    required double amount,
  }) async {
    await showOrderNotification(
      title: '💳 Payment Required',
      body: 'Your bill is ready. Amount due: \$$amount',
      orderId: orderId,
      branchId: branchId,
      notificationType: 'payment_required',
      playSound: true,
    );
  }

  Future<void> showOrderCompletedNotification({
    required String orderId,
    required String branchId,
  }) async {
    await showOrderNotification(
      title: '🎉 Order Completed!',
      body: 'Your laundry service has been completed successfully',
      orderId: orderId,
      branchId: branchId,
      notificationType: 'order_completed',
      playSound: true,
    );
  }

  Future<void> cancelAllNotifications() async {
    await _notificationsPlugin.cancelAll();
  }

  // Test method to manually trigger notifications for debugging
  Future<void> testAllNotificationSounds() async {
    print('🔊 TEST: Testing all notification sounds');
    
    // Test driver arrived notification
    await showDriverArrivedNotification(
      orderId: 'test_order_123',
      branchId: 'test_branch_456',
      driverName: 'Test Driver',
    );
    
    // Wait a bit between notifications
    await Future.delayed(const Duration(seconds: 2));
    
    // Test delivery arrived notification
    await showDeliveryArrivedNotification(
      orderId: 'test_order_123',
      branchId: 'test_branch_456',
      driverName: 'Test Driver',
      amount: 25.50,
    );
    
    await Future.delayed(const Duration(seconds: 2));
    
    // Test order confirmed notification
    await showOrderConfirmedNotification(
      orderId: 'test_order_123',
      branchId: 'test_branch_456',
    );
    
    await Future.delayed(const Duration(seconds: 2));
    
    // Test payment required notification
    await showPaymentRequiredNotification(
      orderId: 'test_order_123',
      branchId: 'test_branch_456',
      amount: 35.75,
    );
    
    await Future.delayed(const Duration(seconds: 2));
    
    // Test order completed notification
    await showOrderCompletedNotification(
      orderId: 'test_order_123',
      branchId: 'test_branch_456',
    );
    
    print('✅ TEST: All notification sounds tested');
  }
}
