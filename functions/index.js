// =======================================================================
// THIS IS YOUR NEW, COMPLETE index.js FILE
// It contains your 3 original functions AND the new balance function.
// =======================================================================

const functions = require("firebase-functions");
const {onCall} = require("firebase-functions/v2/https");
const {onDocumentUpdated, onDocumentCreated} = require("firebase-functions/v2/firestore"); // Added onDocumentCreated
const {initializeApp} = require("firebase-admin/app");
const {getFirestore, FieldValue} = require("firebase-admin/firestore"); // Added FieldValue
const {getMessaging} = require("firebase-admin/messaging");
const {RecaptchaEnterpriseServiceClient} = require("@google-cloud/recaptcha-enterprise");

initializeApp();

const recaptchaClient = new RecaptchaEnterpriseServiceClient();

// =======================================================================
// YOUR EXISTING FUNCTION 1 (No changes)
// =======================================================================
exports.verifyRecaptcha = onCall(async (request) => {
  // ... your existing code for this function ...
  console.log('=== reCAPTCHA Function Called ===');
  console.log('Request data:', request.data);

  const {token, action} = request.data;

  if (!token) {
    console.error('No token provided');
    throw new Error('Token is required');
  }

  try {
    console.log('Creating assessment for token:', token.substring(0, 50) + '...');

    const projectPath = recaptchaClient.projectPath('elite-laundry-station');
    console.log('Project path:', projectPath);

    const assessmentRequest = {
      assessment: {
        event: {
          token: token,
          siteKey: '6LcBU28rAAAAAGWcZdTsYKRSyo45V1htMuEL7a9z',
          expectedAction: action || 'signup',
        },
      },
      parent: projectPath,
    };

    console.log('Assessment request:', JSON.stringify(assessmentRequest, null, 2));

    const [response] = await recaptchaClient.createAssessment(assessmentRequest);
    console.log('reCAPTCHA response:', JSON.stringify(response, null, 2));

    const score = response.riskAnalysis?.score || 0;
    const valid = response.tokenProperties?.valid || false;

    console.log('Score:', score, 'Valid:', valid);

    // Lower threshold for testing
    const threshold = 0.3;
    const success = valid && score >= threshold;

    console.log('Final result - Success:', success);

    return {
      success: success,
      score: score,
      valid: valid,
      reasons: response.riskAnalysis?.reasons || [],
    };

  } catch (error) {
    console.error('reCAPTCHA verification error:', error);
    console.error('Error details:', error.message);
    console.error('Error stack:', error.stack);

    // Return more detailed error info
    throw new Error(`Verification failed: ${error.message}`);
  }
});

// =======================================================================
// YOUR EXISTING FUNCTION 2 (No changes)
// =======================================================================
exports.sendOrderNotification = onDocumentUpdated(
  "branches/{branchId}/mobileOrders/{orderId}",
  async (event) => {
    // ... your existing code for this function ...
    const change = event.data;
    const db = getFirestore();
    const messaging = getMessaging();
    
    const beforeData = change.before.data();
    const afterData = change.after.data();
    
    console.log('📱 Order status change detected');
    console.log('Before status:', beforeData?.status);
    console.log('After status:', afterData?.status);
    console.log('Order ID:', event.params.orderId);
    console.log('Branch ID:', event.params.branchId);
    
    // Only send notifications when status actually changes
    if (beforeData?.status === afterData?.status) {
      console.log('No status change - skipping notification');
      return null;
    }
    
    const userId = afterData?.userId;
    if (!userId) {
      console.log('No user ID found - skipping notification');
      return null;
    }
    
    try {
      // Get user's FCM token from their profile
      const userDoc = await db.collection('branches')
        .doc(event.params.branchId)
        .collection('mobileUsers')
        .doc(userId)
        .get();
      
      const userData = userDoc.data();
      const fcmToken = userData?.fcmToken;
      
      if (!fcmToken) {
        console.log('No FCM token found for user:', userId);
        return null;
      }
      
      console.log('FCM token found:', fcmToken.substring(0, 20) + '...');
      
      // Determine notification type based on status change
      let notificationType = '';
      let title = '';
      let body = '';
      
      switch (afterData.status) {
        case 'confirmed':
          notificationType = 'order_confirmed';
          title = '✅ Order Confirmed';
          body = 'Your laundry order has been confirmed by the driver';
          break;
          
        case 'en_route':
          notificationType = 'driver_arrived';
          title = '🚗 Driver En Route';
          body = 'Your driver is on the way to collect your laundry';
          break;
          
        case 'arrived':
          notificationType = 'driver_arrived';
          title = '🚗 Driver Has Arrived!';
          body = afterData.driverName 
            ? `${afterData.driverName} is at your location to collect your laundry`
            : 'Driver is at your location to collect your laundry';
          break;
          
        case 'collected':
          notificationType = 'order_completed';
          title = '🎉 Order Collected';
          body = 'Your laundry has been collected and is being processed';
          break;
          
        case 'delivery_arrived':
          notificationType = 'delivery_arrived';
          title = '📦 Delivery Arrived!';
          body = afterData.driverName && afterData.totalAmount
            ? `${afterData.driverName} is here with your clean clothes. Amount: $${afterData.totalAmount}`
            : 'Your clean clothes have arrived!';
          break;
          
        case 'payment_required':
          notificationType = 'payment_required';
          title = '💳 Payment Required';
          body = afterData.totalAmount
            ? `Your bill is ready. Amount due: $${afterData.totalAmount}`
            : 'Your bill is ready for payment';
          break;
          
        default:
          console.log('No notification mapping for status:', afterData.status);
          return null;
      }
      
      console.log('Sending notification:', {
        type: notificationType,
        title: title,
        body: body
      });
      
      // Send the notification
      const message = {
        token: fcmToken,
        notification: {
          title: title,
          body: body
        },
        data: {
          orderId: event.params.orderId,
          branchId: event.params.branchId,
          notificationType: notificationType,
          title: title,
          body: body,
          click_action: 'FLUTTER_NOTIFICATION_CLICK'
        },
        android: {
          priority: 'high'
        },
        apns: {
          payload: {
            aps: {
              sound: 'default',
              badge: 1,
              contentAvailable: true
            }
          }
        }
      };
      
      const response = await messaging.send(message);
      console.log('✅ Notification sent successfully:', response);
      
      return {success: true, messageId: response};
      
    } catch (error) {
      console.error('❌ Error sending notification:', error);
      throw new Error(`Failed to send notification: ${error.message}`);
    }
  }
);

// =======================================================================
// YOUR EXISTING FUNCTION 3 (No changes)
// =======================================================================
exports.testNotification = onCall(async (request) => {
    // ... your existing code for this function ...
    const messaging = getMessaging();
    const {fcmToken, orderId, branchId, notificationType} = request.data;
    
    console.log('� Manual notification test requested');
    console.log('FCM Token:', fcmToken ? fcmToken.substring(0, 20) + '...' : 'None');
    console.log('Order ID:', orderId);
    console.log('Branch ID:', branchId);
    console.log('Notification Type:', notificationType);
    
    if (!fcmToken) {
      throw new Error('FCM token is required');
    }
    
    let title = '';
    let body = '';
    
    switch (notificationType) {
      case 'driver_arrived':
        title = '🚗 Driver Has Arrived!';
        body = 'Test Driver is at your location to collect your laundry';
        break;
      case 'delivery_arrived':
        title = '📦 Delivery Arrived!';
        body = 'Test Driver is here with your clean clothes. Amount: $25.50';
        break;
      case 'order_confirmed':
        title = '✅ Order Confirmed';
        body = 'Your laundry order has been confirmed by the driver';
        break;
      case 'payment_required':
        title = '💳 Payment Required';
        body = 'Your bill is ready. Amount due: $35.75';
        break;
      case 'order_completed':
        title = '🎉 Order Completed!';
        body = 'Your laundry service has been completed successfully';
        break;
      default:
        throw new Error('Invalid notification type');
    }
    
    try {
      const message = {
        token: fcmToken,
        notification: {
          title: title,
          body: body
        },
        data: {
          orderId: orderId || 'test_order_123',
          branchId: branchId || 'test_branch_456',
          notificationType: notificationType,
          title: title,
          body: body,
          click_action: 'FLUTTER_NOTIFICATION_CLICK'
        },
        android: {
          priority: 'high'
        }
      };
      
      const response = await messaging.send(message);
      console.log('✅ Test notification sent successfully:', response);
      
      return {
        success: true,
        messageId: response,
        notification: {title, body}
      };
      
    } catch (error) {
      console.error('❌ Error sending test notification:', error);
      throw new Error(`Test notification failed: ${error.message}`);
    }
});


// =======================================================================
// === ADD THIS ENTIRE NEW FUNCTION TO THE END OF YOUR FILE ===
// This is the function that handles the balance transfer.
// =======================================================================
exports.processBalanceTransfer = onDocumentCreated({
  document: "balance_transfers/{transferId}",
  region: "europe-west1" // Must match the trigger region
}, async (event) => {
  const transferId = event.params.transferId;
  console.log(`[START] Processing transferId: ${transferId}`);

  const transferData = event.data.data();
  console.log("  [DATA] Received transfer data:", JSON.stringify(transferData, null, 2));

  const {
    senderId,
    senderBranchId,
    recipientId,
    recipientBranchId,
    amount,
    note,
  } = transferData;

  const db = getFirestore();

  if (!senderId || !recipientId || !senderBranchId || !recipientBranchId || !amount || amount <= 0) {
    console.error("  [VALIDATION_FAILED] Transfer data is invalid.");
    return event.data.ref.update({
      status: "failed",
      error: "Invalid or incomplete transfer data provided.",
      processedAt: FieldValue.serverTimestamp(),
    });
  }
  console.log("  [VALIDATION_PASSED] Transfer data is valid.");

  const senderBalanceRef = db.doc(`branches/${senderBranchId}/mobileUsers/${senderId}/user_eBalance/balance`);
  const recipientBalanceRef = db.doc(`branches/${recipientBranchId}/mobileUsers/${recipientId}/user_eBalance/balance`);

  console.log(`  [PATH_SENDER] Sender balance path: ${senderBalanceRef.path}`);
  console.log(`  [PATH_RECIPIENT] Recipient balance path: ${recipientBalanceRef.path}`);

  try {
    await db.runTransaction(async (transaction) => {
      console.log("    [TRANSACTION_START] Beginning transaction.");
      const [senderBalanceDoc, recipientBalanceDoc] = await Promise.all([
        transaction.get(senderBalanceRef),
        transaction.get(recipientBalanceRef),
      ]);
      console.log(`    [READ_SUCCESS] Sender exists: ${senderBalanceDoc.exists}, Recipient exists: ${recipientBalanceDoc.exists}`);

      if (!senderBalanceDoc.exists) {
        throw new Error(`Sender balance document does not exist.`);
      }

      const senderBalance = senderBalanceDoc.data()?.main_balance ?? 0;
      console.log(`    [LOGIC] Sender's balance: ${senderBalance}. Amount to send: ${amount}`);

      if (senderBalance < amount) {
        throw new Error("Insufficient funds.");
      }

      const newSenderBalance = senderBalance - amount;
      const recipientBalance = recipientBalanceDoc.data()?.main_balance ?? 0;
      const newRecipientBalance = recipientBalance + amount;
      const timestamp = FieldValue.serverTimestamp();

      console.log(`    [CALC] New Sender Balance: ${newSenderBalance}, New Recipient Balance: ${newRecipientBalance}`);
      console.log("    [WRITE] Scheduling all writes...");

      transaction.update(senderBalanceRef, { main_balance: newSenderBalance, lastUpdated: timestamp });

      if (recipientBalanceDoc.exists) {
        transaction.update(recipientBalanceRef, { main_balance: newRecipientBalance, lastUpdated: timestamp });
      } else {
        transaction.set(recipientBalanceRef, { main_balance: newRecipientBalance, percent_balance: 0, lastUpdated: timestamp });
      }

      const senderHistoryRef = db.collection(`branches/${senderBranchId}/mobileUsers/${senderId}/balance_transactions`).doc();
      transaction.set(senderHistoryRef, { type: "send", amount: -amount, recipientId, note, timestamp, status: "completed" });
      
      const recipientHistoryRef = db.collection(`branches/${recipientBranchId}/mobileUsers/${recipientId}/balance_transactions`).doc();
      transaction.set(recipientHistoryRef, { type: "receive", amount, senderId, note, timestamp, status: "completed" });
      
      transaction.update(event.data.ref, { status: "completed", processedAt: timestamp });
      console.log("    [TRANSACTION_COMMIT] All writes scheduled.");
    });

    console.log(`[SUCCESS] Successfully processed transferId: ${transferId}.`);
    return null;

  } catch (error) {
    console.error(`  [TRANSACTION_FAILED] Error processing transfer ${transferId}:`, error.message);
    return event.data.ref.update({
      status: "failed",
      error: error.message,
      processedAt: FieldValue.serverTimestamp(),
    });
  }
});
