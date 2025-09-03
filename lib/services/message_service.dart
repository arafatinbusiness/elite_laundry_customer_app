import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/message_models.dart';

class MessageService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get currentUserId => _auth.currentUser?.uid;

  String createConversationId(String customerId, String agentId, String agentType) {
    return '${customerId}_${agentId}_$agentType';
  }

  Stream<List<Conversation>> getConversations() {
    if (currentUserId == null) return Stream.value([]);

    try {
      return _firestore
          .collection('conversations')
          .where('participants', arrayContains: currentUserId)
          .orderBy('lastUpdated', descending: true)
          .snapshots()
          .map((snapshot) => snapshot.docs
          .map((doc) => Conversation.fromFirestore(doc))
          .toList())
          .handleError((error) {
        print('Error getting conversations: $error');
        return <Conversation>[];
      });
    } catch (e) {
      print('Error in getConversations: $e');
      return Stream.value([]);
    }
  }


  Stream<List<Message>> getMessages(String conversationId) {
    return _firestore
        .collection('messages')
        .doc(conversationId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => Message.fromFirestore(doc))
        .toList());
  }

  Future<void> sendMessage({
    required String conversationId,
    required String receiverId,
    required String message,
    required String senderType,
  }) async {
    if (currentUserId == null) return;

    final messageData = Message(
      id: '',
      senderId: currentUserId!,
      receiverId: receiverId,
      message: message,
      timestamp: DateTime.now(),
      isRead: false,
      senderType: senderType,
    );

    await _firestore
        .collection('messages')
        .doc(conversationId)
        .collection('messages')
        .add(messageData.toMap());

    await _updateConversationLastMessage(conversationId, message, senderType);
  }

  Future<void> _updateConversationLastMessage(
      String conversationId,
      String lastMessage,
      String senderType,
      ) async {
    try {
      final conversationRef = _firestore.collection('conversations').doc(conversationId);
      final updateData = {
        'lastMessage': lastMessage,
        'lastUpdated': Timestamp.now(),
      };

      if (senderType == 'customer') {
        updateData['agentUnreadCount'] = FieldValue.increment(1);
      } else {
        updateData['customerUnreadCount'] = FieldValue.increment(1);
      }

      await conversationRef.set(updateData, SetOptions(merge: true));
    } catch (e) {
      print('Error updating conversation: $e');
      // Don't rethrow to avoid breaking message sending
    }
  }

  Future<void> markAsRead(String conversationId, String userType) async {
    if (currentUserId == null) return;

    final conversationRef = _firestore.collection('conversations').doc(conversationId);

    final updateData = userType == 'customer'
        ? {'customerUnreadCount': 0}
        : {'agentUnreadCount': 0};

    await conversationRef.update(updateData);
  }

  Future<String> createConversation({
    required String customerId,
    required String agentId,
    required String agentType,
    String? customerName,
    String? agentName,
  }) async {
    final conversationId = createConversationId(customerId, agentId, agentType);

    try {
      final conversationData = Conversation(
        id: conversationId,
        participants: [customerId, agentId],
        agentType: agentType,
        agentId: agentId,
        customerId: customerId,
        lastUpdated: DateTime.now(),
        customerName: customerName,
        agentName: agentName,
        customerUnreadCount: 0, // Initialize counts
        agentUnreadCount: 0,
      );

      // This is the fix. .set() with merge:true will create the doc if it's new,
      // or harmlessly update it if it exists. This is a WRITE operation,
      // which your security rules allow. It avoids the forbidden READ.
      await _firestore
          .collection('conversations')
          .doc(conversationId)
          .set(conversationData.toMap(), SetOptions(merge: true));

      return conversationId;
    } catch (e) {
      print('Error creating/merging conversation: $e');
      rethrow;
    }
  }

  Stream<int> getUnreadCount() {
    if (currentUserId == null) return Stream.value(0);

    return _firestore
        .collection('conversations')
        .where('participants', arrayContains: currentUserId)
        .snapshots()
        .map((snapshot) {
      int totalUnread = 0;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        totalUnread += (data['customerUnreadCount'] as int? ?? 0);
      }
      return totalUnread;
    });
  }
}
