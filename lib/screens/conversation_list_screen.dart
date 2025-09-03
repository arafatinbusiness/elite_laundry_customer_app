import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/message_service.dart';
import '../../models/message_models.dart';
import 'messages_screen.dart';
import 'package:timeago/timeago.dart' as timeago;

class ConversationListScreen extends StatefulWidget {
  @override
  _ConversationListScreenState createState() => _ConversationListScreenState();
}

class _ConversationListScreenState extends State<ConversationListScreen> {
  final MessageService _messageService = MessageService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Messages'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<Conversation>>(
        stream: _messageService.getConversations(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.message_outlined,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No conversations yet',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Start a conversation with your laundry service',
                    style: TextStyle(
                      color: Colors.grey[500],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          final conversations = snapshot.data!;
          return ListView.builder(
            itemCount: conversations.length,
            itemBuilder: (context, index) {
              final conversation = conversations[index];
              return _buildConversationTile(conversation);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _startNewConversation,
        child: Icon(Icons.add),
        backgroundColor: Theme.of(context).primaryColor,
      ),
    );
  }

  Widget _buildConversationTile(Conversation conversation) {
    final isUnread = conversation.customerUnreadCount > 0;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).primaryColor.withOpacity(0.2),
        child: Icon(
          Icons.business,
          color: Theme.of(context).primaryColor,
        ),
      ),
      title: Text(
        conversation.agentName ?? 'Laundry Service',
        style: TextStyle(
          fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        conversation.lastMessage ?? 'No messages yet',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isUnread ? Colors.black87 : Colors.grey[600],
          fontWeight: isUnread ? FontWeight.w500 : FontWeight.normal,
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (conversation.lastUpdated != null)
            Text(
              timeago.format(conversation.lastUpdated!),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
              ),
            ),
          if (isUnread) ...[
            SizedBox(height: 4),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${conversation.customerUnreadCount}',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MessagesScreen(
              conversationId: conversation.id,
              receiverId: conversation.agentId,
              receiverName: conversation.agentName ?? 'Laundry Service',
            ),
          ),
        );
      },
    );
  }

  Future<void> _startNewConversation() async {
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(
          child: CircularProgressIndicator(),
        ),
      );

      // Get current user
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        Navigator.pop(context); // Close loading dialog
        _showError('Please log in to start a conversation');
        return;
      }

      // Get user's branch information
      final userBranchData = await _getUserBranchData(currentUser.uid);
      if (userBranchData == null) {
        Navigator.pop(context); // Close loading dialog
        _showError('Unable to find your branch information');
        return;
      }

      // Get branch details
      final branchData = await _getBranchData(userBranchData['branchId']);
      if (branchData == null) {
        Navigator.pop(context); // Close loading dialog
        _showError('Unable to find branch details');
        return;
      }

      // Create conversation with the local branch
      final conversationId = await _messageService.createConversation(
        customerId: currentUser.uid,
        agentId: branchData['managerId'], // Use managerId as agent ID
        agentName: branchData['name'], // Branch name
        agentType: 'localBranch',
      );

      // Close loading dialog
      Navigator.pop(context);

      // Navigate to messages screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MessagesScreen(
            conversationId: conversationId,
            receiverId: branchData['managerId'],
            receiverName: branchData['name'],
          ),
        ),
      );

    } catch (e) {
      // Close loading dialog if still open
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      _showError('Failed to start conversation: $e');
    }
  }

  Future<Map<String, dynamic>?> _getUserBranchData(String userId) async {
    try {
      // Query all branches to find where this user exists
      final branchesSnapshot = await _firestore.collection('branches').get();

      for (final branchDoc in branchesSnapshot.docs) {
        final userDoc = await _firestore
            .collection('branches')
            .doc(branchDoc.id)
            .collection('mobileUsers')
            .doc(userId)
            .get();

        if (userDoc.exists) {
          final userData = userDoc.data()!;
          userData['branchId'] = branchDoc.id; // Add branch ID to user data
          return userData;
        }
      }
      return null;
    } catch (e) {
      print('Error getting user branch data: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _getBranchData(String branchId) async {
    try {
      final branchDoc = await _firestore
          .collection('branches')
          .doc(branchId)
          .get();

      if (branchDoc.exists) {
        return branchDoc.data();
      }
      return null;
    } catch (e) {
      print('Error getting branch data: $e');
      return null;
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }
}
