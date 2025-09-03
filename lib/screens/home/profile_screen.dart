import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  
  late User _user;
  Map<String, dynamic>? _userData;
  Map<String, dynamic>? _branchData;
  bool _isLoading = true;
  bool _isEditing = false;
  bool _isSaving = false;

  // Form controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _countryController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      _user = user;

      // Get user document from Firestore
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        _userData = userDoc.data() as Map<String, dynamic>;
        
        // Load branch data if available
        final branchId = _userData?['branchId'];
        if (branchId != null) {
          final branchDoc = await _firestore.collection('branches').doc(branchId).get();
          if (branchDoc.exists) {
            _branchData = branchDoc.data() as Map<String, dynamic>;
          }
        }

        // Initialize form controllers
        _nameController.text = _userData?['name'] ?? user.displayName ?? '';
        _phoneController.text = _userData?['phone'] ?? '';
        _emailController.text = user.email ?? '';
        _cityController.text = _userData?['city'] ?? '';
        _countryController.text = _userData?['country'] ?? '';
        _addressController.text = _userData?['locationData']?['address'] ?? '';
      }

      setState(() => _isLoading = false);
    } catch (e) {
      print('Error loading user data: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    if (!_isEditing) {
      setState(() => _isEditing = true);
      return;
    }

    setState(() => _isSaving = true);

    try {
      final updates = {
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'city': _cityController.text.trim(),
        'country': _countryController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Update user document
      await _firestore.collection('users').doc(_user.uid).update(updates);

      // Update Firebase Auth display name
      await _user.updateDisplayName(_nameController.text.trim());

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      setState(() {
        _isEditing = false;
        _isSaving = false;
      });

      // Reload data to reflect changes
      await _loadUserData();

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update profile: $e'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() => _isSaving = false);
    }
  }

  void _cancelEdit() {
    // Reset form values
    _nameController.text = _userData?['name'] ?? _user.displayName ?? '';
    _phoneController.text = _userData?['phone'] ?? '';
    _cityController.text = _userData?['city'] ?? '';
    _countryController.text = _userData?['country'] ?? '';
    
    setState(() => _isEditing = false);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _cityController.dispose();
    _countryController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: const Color(0xFF1E40AF),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _isSaving ? null : _cancelEdit,
            ),
          IconButton(
            icon: _isEditing ? const Icon(Icons.save) : const Icon(Icons.edit),
            onPressed: _isSaving ? null : _saveProfile,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildProfileHeader(),
                  const SizedBox(height: 24),
                  _buildProfileForm(),
                  const SizedBox(height: 24),
                  _buildBranchInfo(),
                  const SizedBox(height: 24),
                  _buildLogoutButton(),
                ],
              ),
            ),
    );
  }

  Widget _buildProfileHeader() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: const Color(0xFF1E40AF),
              child: Text(
                (_userData?['name'] ?? _user.displayName ?? 'U').substring(0, 1).toUpperCase(),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _userData?['name'] ?? _user.displayName ?? 'User',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _user.email ?? 'No email',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Total Orders: ${_userData?['totalOrders'] ?? 0}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileForm() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Personal Information',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 16),
            _buildEditableField(
              label: 'Full Name',
              controller: _nameController,
              icon: Icons.person,
              enabled: _isEditing,
            ),
            const SizedBox(height: 12),
            _buildEditableField(
              label: 'Phone Number',
              controller: _phoneController,
              icon: Icons.phone,
              keyboardType: TextInputType.phone,
              enabled: _isEditing,
            ),
            const SizedBox(height: 12),
            _buildEditableField(
              label: 'Email',
              controller: _emailController,
              icon: Icons.email,
              enabled: false, // Email cannot be changed
            ),
            const SizedBox(height: 12),
            _buildEditableField(
              label: 'City',
              controller: _cityController,
              icon: Icons.location_city,
              enabled: _isEditing,
            ),
            const SizedBox(height: 12),
            _buildEditableField(
              label: 'Country',
              controller: _countryController,
              icon: Icons.public,
              enabled: _isEditing,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditableField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    bool enabled = true,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        filled: !enabled,
        fillColor: !enabled ? Colors.grey[100] : null,
      ),
    );
  }

  Widget _buildBranchInfo() {
    if (_branchData == null) return const SizedBox();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your Laundry Branch',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.local_laundry_service, color: Color(0xFF1E40AF)),
              title: Text(
                _branchData?['branchName'] ?? 'Elite Laundry',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: Text(_branchData?['address'] ?? ''),
            ),
            ListTile(
              leading: const Icon(Icons.phone, color: Color(0xFF1E40AF)),
              title: const Text('Branch Phone'),
              subtitle: Text(_branchData?['phone'] ?? '+966564398680'),
            ),
            ListTile(
              leading: const Icon(Icons.email, color: Color(0xFF1E40AF)),
              title: const Text('Branch Email'),
              subtitle: Text(_branchData?['email'] ?? 'elitelaundryb1@gmail.com'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.lock, color: Color(0xFF1E40AF)),
            title: const Text('Change Password'),
            onTap: _handleChangePassword,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text(
              'Logout',
              style: TextStyle(color: Colors.red),
            ),
            onTap: () => _handleLogout(context),
          ),
        ],
      ),
    );
  }

  Future<void> _handleChangePassword() async {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    bool isLoading = false;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Change Password'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: currentPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Current Password',
                      border: OutlineInputBorder(),
                    ),
                    enabled: !isLoading,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: newPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'New Password',
                      border: OutlineInputBorder(),
                    ),
                    enabled: !isLoading,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: confirmPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirm New Password',
                      border: OutlineInputBorder(),
                    ),
                    enabled: !isLoading,
                    onChanged: (value) {
                      if (value.isNotEmpty && value != newPasswordController.text) {
                        // Show error if passwords don't match
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          if (newPasswordController.text != confirmPasswordController.text) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('New passwords do not match'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }

                          if (newPasswordController.text.length < 6) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('New password must be at least 6 characters'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }

                          setState(() => isLoading = true);

                          try {
                            // Reauthenticate user with current password
                            final credential = EmailAuthProvider.credential(
                              email: _user.email!,
                              password: currentPasswordController.text,
                            );

                            await _user.reauthenticateWithCredential(credential);

                            // Update password
                            await _user.updatePassword(newPasswordController.text);

                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Password changed successfully!'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } on FirebaseAuthException catch (e) {
                            setState(() => isLoading = false);
                            String errorMessage;
                            switch (e.code) {
                              case 'wrong-password':
                                errorMessage = 'Current password is incorrect';
                                break;
                              case 'weak-password':
                                errorMessage = 'New password is too weak';
                                break;
                              default:
                                errorMessage = 'Failed to change password: ${e.message}';
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(errorMessage),
                                backgroundColor: Colors.red,
                              ),
                            );
                          } catch (e) {
                            setState(() => isLoading = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to change password: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                  child: isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Change Password'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _handleLogout(BuildContext context) async {
    try {
      await _auth.signOut();
      if (context.mounted) {
        Navigator.pushReplacementNamed(context, '/');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Logout failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
