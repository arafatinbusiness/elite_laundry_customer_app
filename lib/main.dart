import 'package:elite_laundry_customer_app/screens/login_screen.dart';
import 'package:elite_laundry_customer_app/screens/signup_screen.dart';
import 'package:elite_laundry_customer_app/screens/home/customer_order_tracking_screen.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:elite_laundry_customer_app/services/notification_service.dart';
import 'screens/welcome/welcome_screen.dart';
import 'screens/select_location_screen.dart';
import 'screens/service_selection_screen.dart';
import 'screens/home/home_screen.dart';
import 'firebase_options.dart';

// Global navigator key to access the navigator from outside the widget tree
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Handles background messages when the app is not active.
/// It must be a top-level function and not an anonymous function.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Ensure Firebase is initialized for the background isolate.
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  print("Handling a background message: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Only initialize Firebase core here - minimal initialization
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await FirebaseAppCheck.instance.activate(
    // You can provider your own token provider or use the default.
   // webProvider: ReCaptchaV3Provider('recaptcha-v3-site-key'), // Replace with your key
    androidProvider: AndroidProvider.debug, // Use debug for testing, playintegrity for production
    appleProvider: AppleProvider.debug, // Use debug for testing, appattest for production
  );
  // Set the background messaging handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(const MyApp());
}

// MODIFICATION: Converted to a StatefulWidget to use initState
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    // Defer heavy initialization to after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupFirebaseMessaging();
    });
  }

  /// Sets up Firebase Messaging handlers and requests user permissions.
  void _setupFirebaseMessaging() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    // Initialize notification service
    await NotificationService().initialize();

    // 1. Request Notification Permissions
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    print('User granted permission: ${settings.authorizationStatus}');

    // Get and save FCM token for current user
    await _saveFcmToken();

    // Listen for token refresh
    FirebaseMessaging.instance.onTokenRefresh.listen((String newToken) async {
      print('🔄 FCM token refreshed: ${newToken.substring(0, 20)}...');
      await _saveFcmToken();
    });

    // 2. Handle Foreground Messages - Show local notifications
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('📨 DEBUG: Received foreground message - ID: ${message.messageId}');
      print('📨 DEBUG: Message data: ${message.data}');
      
      // Show local notification for order status changes
      if (message.data.containsKey('orderId') && 
          message.data.containsKey('branchId') &&
          message.data.containsKey('notificationType')) {
        
        final String orderId = message.data['orderId']!;
        final String branchId = message.data['branchId']!;
        final String notificationType = message.data['notificationType']!;
        final String title = message.notification?.title ?? 'Order Update';
        final String body = message.notification?.body ?? 'Your order status has changed';

        print('📨 DEBUG: Processing order notification - Order: $orderId, Type: $notificationType');
        
        // Show appropriate notification based on type
        _showOrderNotification(
          title: title,
          body: body,
          orderId: orderId,
          branchId: branchId,
          notificationType: notificationType,
        );
        
        print('📨 DEBUG: Notification request sent to _showOrderNotification');
      } else {
        print('📨 DEBUG: Message does not contain required order data');
      }
    });

    // 3. Handle Notification Taps (opening the app from terminated state)
    FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        _handleNotificationClick(message);
      }
    });

    // 4. Handle Notification Taps (opening the app from background state)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleNotificationClick(message);
    });
  }

  /// Saves the FCM token to the current user's document in Firestore
  Future<void> _saveFcmToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('⚠️  No user logged in - cannot save FCM token');
        return;
      }

      // Get the FCM token
      final String? token = await FirebaseMessaging.instance.getToken();
      if (token == null) {
        print('⚠️  No FCM token available');
        return;
      }

      print('✅ FCM token obtained: ${token.substring(0, 20)}...');

      // Try to get the user's actual branch ID from their orders
      String? branchId = await _getUserBranchId();
      if (branchId == null) {
        print('⚠️  No branch ID found for user - cannot save FCM token');
        return;
      }

      // Save token to user's document
      final db = FirebaseFirestore.instance;
      await db.collection('branches')
          .doc(branchId)
          .collection('mobileUsers')
          .doc(user.uid)
          .set({
            'fcmToken': token,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      print('✅ FCM token saved to user document in branch: $branchId');
      
    } catch (e) {
      print('❌ Error saving FCM token: $e');
    }
  }

  /// Tries to get the user's branch ID from their existing orders
  Future<String?> _getUserBranchId() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;

      final db = FirebaseFirestore.instance;
      
      // Try to find any order for this user to get the branch ID
      final ordersQuery = await db.collectionGroup('mobileOrders')
          .where('userId', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (ordersQuery.docs.isNotEmpty) {
        final orderData = ordersQuery.docs.first.data();
        final branchId = orderData['branchId'] as String?;
        if (branchId != null) {
          print('✅ Found user branch ID from existing order: $branchId');
          return branchId;
        }
      }

      print('⚠️  No existing orders found for user, using default branch ID');
      return null;
    } catch (e) {
      print('❌ Error getting user branch ID: $e');
      return null;
    }
  }

  /// Shows appropriate order notification based on type
  void _showOrderNotification({
    required String title,
    required String body,
    required String orderId,
    required String branchId,
    required String notificationType,
  }) {
    print('🔔 DEBUG: _showOrderNotification called - Type: $notificationType, Order: $orderId');
    final notificationService = NotificationService();
    
    switch (notificationType) {
      case 'driver_arrived':
        notificationService.showDriverArrivedNotification(
          orderId: orderId,
          branchId: branchId,
          driverName: body.contains('driver') ? 'Driver' : 'Delivery Personnel',
        );
        break;
      case 'delivery_arrived':
        // Extract amount from body if available
        final amountMatch = RegExp(r'\$(\d+\.?\d*)').firstMatch(body);
        final amount = amountMatch != null ? double.parse(amountMatch.group(1)!) : 0.0;
        notificationService.showDeliveryArrivedNotification(
          orderId: orderId,
          branchId: branchId,
          driverName: 'Driver',
          amount: amount,
        );
        break;
      case 'order_confirmed':
        notificationService.showOrderConfirmedNotification(
          orderId: orderId,
          branchId: branchId,
        );
        break;
      case 'payment_required':
        final amountMatch = RegExp(r'\$(\d+\.?\d*)').firstMatch(body);
        final amount = amountMatch != null ? double.parse(amountMatch.group(1)!) : 0.0;
        notificationService.showPaymentRequiredNotification(
          orderId: orderId,
          branchId: branchId,
          amount: amount,
        );
        break;
      case 'order_completed':
        notificationService.showOrderCompletedNotification(
          orderId: orderId,
          branchId: branchId,
        );
        break;
      default:
        // Generic order notification
        notificationService.showOrderNotification(
          title: title,
          body: body,
          orderId: orderId,
          branchId: branchId,
          notificationType: notificationType,
        );
    }
  }

  /// Centralized handler for navigating when a notification is clicked.
  void _handleNotificationClick(RemoteMessage message) {
    // Example navigation logic:
    // Check the message data payload for specific keys to decide where to navigate.
    if (message.data.containsKey('orderId') && message.data.containsKey('branchId')) {
      navigatorKey.currentState?.pushNamed(
        '/order-tracking',
        arguments: {
          'orderId': message.data['orderId'],
          'branchId': message.data['branchId'],
        },
      );
    }
  }

  // Method to test notifications manually
  Future<void> _testNotifications() async {
    print('🔔 TEST: Manually testing notifications');
    final notificationService = NotificationService();
    await notificationService.testAllNotificationSounds();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Elite Laundry Customer App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      // CRITICAL: Assign the navigatorKey here
      navigatorKey: navigatorKey,
      home: const AuthWrapper(),
      routes: {
        '/welcome': (context) => const WelcomeScreen(),
        '/login': (context) => const LoginScreen(),
        '/select-location': (context) => const SelectLocationScreen(),
        '/service-selection': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
          return ServiceSelectionScreen(locationData: args);
        },
        '/signup': (context) {
          final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
          return SignupScreen(locationData: args);
        },
        '/home': (context) => const HomeScreen(),
        '/order-tracking': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
          return CustomerOrderTrackingScreen(
            orderId: args['orderId'] as String,
            branchId: args['branchId'] as String,
          );
        },
      },
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasData && snapshot.data != null) {
          return const HomeScreen();
        }

        return const WelcomeScreen();
      },
    );
  }
}
