import 'package:cloud_firestore/cloud_firestore.dart';

class Message {
  final String id;
  final String senderId;
  final String receiverId;
  final String message;
  final DateTime timestamp;
  final bool isRead;
  final String senderType; // 'customer' or 'agent'

  Message({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.message,
    required this.timestamp,
    required this.isRead,
    required this.senderType,
  });

  factory Message.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Message(
      id: doc.id,
      senderId: data['senderId'] ?? '',
      receiverId: data['receiverId'] ?? '',
      message: data['message'] ?? '',
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      isRead: data['isRead'] ?? false,
      senderType: data['senderType'] ?? 'customer',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'receiverId': receiverId,
      'message': message,
      'timestamp': Timestamp.fromDate(timestamp),
      'isRead': isRead,
      'senderType': senderType,
    };
  }
}

class Conversation {
  final String id;
  final List<String> participants;
  final String agentType; // 'cityAgent' or 'localBranch'
  final String agentId;
  final String customerId;
  final String? lastMessage;
  final DateTime? lastUpdated;
  final int customerUnreadCount;
  final int agentUnreadCount;
  final String? customerName;
  final String? agentName;

  Conversation({
    required this.id,
    required this.participants,
    required this.agentType,
    required this.agentId,
    required this.customerId,
    this.lastMessage,
    this.lastUpdated,
    this.customerUnreadCount = 0,
    this.agentUnreadCount = 0,
    this.customerName,
    this.agentName,
  });

  factory Conversation.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Conversation(
      id: doc.id,
      participants: List<String>.from(data['participants'] ?? []),
      agentType: data['agentType'] ?? 'cityAgent',
      agentId: data['agentId'] ?? '',
      customerId: data['customerId'] ?? '',
      lastMessage: data['lastMessage'],
      lastUpdated: data['lastUpdated'] != null
          ? (data['lastUpdated'] as Timestamp).toDate()
          : null,
      customerUnreadCount: data['customerUnreadCount'] ?? 0,
      agentUnreadCount: data['agentUnreadCount'] ?? 0,
      customerName: data['customerName'],
      agentName: data['agentName'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'participants': participants,
      'agentType': agentType,
      'agentId': agentId,
      'customerId': customerId,
      'lastMessage': lastMessage,
      'lastUpdated': lastUpdated != null ? Timestamp.fromDate(lastUpdated!) : null,
      'customerUnreadCount': customerUnreadCount,
      'agentUnreadCount': agentUnreadCount,
      'customerName': customerName,
      'agentName': agentName,
    };
  }
}
