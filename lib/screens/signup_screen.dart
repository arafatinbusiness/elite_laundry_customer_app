import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:email_validator/email_validator.dart';

class SignupScreen extends StatefulWidget {
  final Map<String, dynamic>? locationData;

  const SignupScreen({Key? key, this.locationData}) : super(key: key);

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  // Controllers
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  // State variables
  bool _isLoading = false;
  bool _emailVerified = false;
  bool _phoneVerified = false;
  bool _otpSent = false;
  bool _useEmailLogin = true; // Toggle between email/phone login
  bool _showPassword = false;
  bool _showConfirmPassword = false;
  String? _verificationId;
  String? _emailError;
  String? _phoneError;

  String get branchId => widget.locationData?['branchData']?['id'] ?? '';

  @override
  void dispose() {
    _phoneCheckTimer?.cancel();
    _emailCheckTimer?.cancel();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
// Real-time email validation with existence check
  void _validateEmail(String email) {
    setState(() {
      if (email.isEmpty) {
        _emailError = null;
        _emailVerified = false;
      } else if (!EmailValidator.validate(email)) {
        _emailError = 'Invalid email format';
        _emailVerified = false;
      } else {
        // Format is valid, now check existence
        _emailError = null;
        _emailVerified = true; // Temporarily set to true while checking

        // Check for existing email in real-time (debounced)
        _debounceEmailCheck(email);
      }
    });
  }


  Timer? _emailCheckTimer;

  void _debounceEmailCheck(String email) {
    _emailCheckTimer?.cancel();
    _emailCheckTimer = Timer(Duration(milliseconds: 1500), () async {
      // Only check if the email hasn't changed and widget is still mounted
      if (email == _emailController.text.trim() && mounted) {
        print('🔍 Debounced email check for: $email');

        final exists = await _checkEmailExists(email);

        // Only update if the email field hasn't changed during the check
        if (email == _emailController.text.trim() && mounted) {
          setState(() {
            if (exists) {
              _emailError = 'Email already registered';
              _emailVerified = false;
            } else {
              _emailError = null;
              _emailVerified = true;
            }
          });
        }
      }
    });
  }


  // Real-time phone validation
  void _validatePhone(String phone) {
    setState(() {
      if (phone.isEmpty) {
        _phoneError = null;
        _phoneVerified = false;
      } else if (phone.length >= 10 && RegExp(r'^\+?[\d\s\-()]+$').hasMatch(phone)) {
        _phoneError = null;
        _phoneVerified = true;

        // Optional: Check for existing phone in real-time (debounced)
        _debouncePhoneCheck(phone);
      } else {
        _phoneError = 'Invalid phone number';
        _phoneVerified = false;
      }
    });
  }


  Timer? _phoneCheckTimer;

  void _debouncePhoneCheck(String phone) {
    _phoneCheckTimer?.cancel();
    _phoneCheckTimer = Timer(Duration(milliseconds: 1000), () async {
      if (phone == _phoneController.text.trim()) {
        final exists = await _checkPhoneExists(phone);
        if (exists && mounted) {
          setState(() {
            _phoneError = 'Phone number already registered';
            _phoneVerified = false;
          });
        }
      }
    });
  }

// Add this method after _validatePhone
Future<bool> _checkPhoneExists(String phone) async {
  try {
    print('🔍 Checking if phone exists: $phone');

    // Check in global users collection
    final globalQuery = await _firestore
        .collection('users')
        .where('phone', isEqualTo: phone.trim())
        .limit(1)
        .get();

    if (globalQuery.docs.isNotEmpty) {
      print('❌ Phone found in global users collection');
      return true;
    }

    // Also check in current branch's mobileUsers collection
    final branchQuery = await _firestore
        .collection('branches')
        .doc(branchId)
        .collection('mobileUsers')
        .where('phone', isEqualTo: phone.trim())
        .limit(1)
        .get();

    if (branchQuery.docs.isNotEmpty) {
      print('❌ Phone found in branch mobileUsers collection');
      return true;
    }

    print('✅ Phone number is available');
    return false;
  } catch (e) {
    print('❌ Error checking phone existence: $e');
    // In case of error, allow signup to proceed
    return false;
  }
}

  // Add this method after _validatePhone
  bool _canCompleteSignup() {
    final passwordValid = _passwordController.text.length >= 6;
    return _phoneVerified && passwordValid;
  }




  // Send SMS OTP with reCAPTCHA verification
  Future<void> _sendOTP() async {
    if (!_phoneVerified) return;

    setState(() => _isLoading = true);

    try {
      // Verify reCAPTCHA before sending OTP
      final recaptchaValid = await _verifyRecaptcha('send_otp');
      if (!recaptchaValid) {
        _showError('Security verification failed. Please try again.');
        return;
      }

      await _auth.verifyPhoneNumber(
        phoneNumber: _phoneController.text.trim(),
        verificationCompleted: (PhoneAuthCredential credential) async {
          setState(() {
            _phoneVerified = true;
            _otpSent = true;
          });
        },
        verificationFailed: (FirebaseAuthException e) {
          _showError('Phone verification failed: ${e.message}');
        },
        codeSent: (String verificationId, int? resendToken) {
          setState(() {
            _verificationId = verificationId;
            _otpSent = true;
          });
          _showSuccess('OTP sent to ${_phoneController.text}');
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
        timeout: const Duration(seconds: 60),
      );
    } catch (e) {
      _showError('Failed to send OTP: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }


  // Verify OTP
  Future<void> _verifyOTP() async {
    if (_otpController.text.length != 6) return;

    setState(() => _isLoading = true);

    try {
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: _otpController.text.trim(),
      );

      // Just verify the credential without signing in
      await FirebaseAuth.instance.signInWithCredential(credential);
      await FirebaseAuth.instance.signOut(); // Sign out immediately

      setState(() => _phoneVerified = true);
      _showSuccess('Phone number verified!');
    } catch (e) {
      _showError('Invalid OTP');
    } finally {
      setState(() => _isLoading = false);
    }
  }



  // Add this method after your existing methods
  Future<bool> _verifyRecaptcha(String action) async {
    print('TEMPORARY: Bypassing reCAPTCHA verification');
    return true; // Always return true for now
  }





// Complete signup with phone uniqueness check
  Future<void> _completeSignup() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_phoneVerified) {
      _showError('Please verify your phone number');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Check if phone number already exists
      final phoneExists = await _checkPhoneExists(_phoneController.text.trim());
      if (phoneExists) {
        _showError('An account with this phone number already exists. Please use a different phone number or try logging in.');
        return;
      }

      final recaptchaValid = await _verifyRecaptcha('signup');
      if (!recaptchaValid) {
        _showError('Security verification failed. Please try again.');
        return;
      }

      UserCredential userCredential;
      String emailForAuth;

      if (_emailController.text.isNotEmpty) {
        // Check if email already exists too
        final emailExists = await _checkEmailExists(_emailController.text.trim());
        if (emailExists) {
          _showError('An account with this email already exists. Please use a different email or try logging in.');
          return;
        }

        emailForAuth = _emailController.text.trim();
        print('SIGNUP: Using provided email: $emailForAuth');
      } else {
        emailForAuth = _phoneController.text.trim()
            .replaceAll('+', '')
            .replaceAll(' ', '')
            .replaceAll('-', '')
            .replaceAll('(', '')
            .replaceAll(')', '') + '@phone.local';
        print('SIGNUP: Generated email from phone: $emailForAuth');
      }

      print('SIGNUP: Creating Firebase Auth user with email: $emailForAuth');
      print('SIGNUP: Password length: ${_passwordController.text.length}');

      userCredential = await _auth.createUserWithEmailAndPassword(
        email: emailForAuth,
        password: _passwordController.text.trim(),
      );

      print('SIGNUP: Firebase Auth user created successfully');
      print('SIGNUP: User UID: ${userCredential.user!.uid}');
      print('SIGNUP: User email from Firebase: ${userCredential.user!.email}');

      await _saveUserData(userCredential.user!);
      print('SIGNUP: User data saved to Firestore');

      Navigator.pushReplacementNamed(context, '/home');
    } on FirebaseAuthException catch (e) {
      print('SIGNUP FIREBASE AUTH ERROR: ${e.code} - ${e.message}');

      String errorMessage;
      switch (e.code) {
        case 'email-already-in-use':
          errorMessage = 'This email is already registered. Please use a different email or try logging in.';
          break;
        case 'weak-password':
          errorMessage = 'Password is too weak. Please choose a stronger password.';
          break;
        case 'invalid-email':
          errorMessage = 'Invalid email format. Please check your email address.';
          break;
        default:
          errorMessage = 'Signup failed: ${e.message}';
      }

      _showError(errorMessage);
    } catch (e) {
      print('SIGNUP ERROR: $e');
      _showError('Signup failed: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }


// Add this method after _checkPhoneExists
  Future<bool> _checkEmailExists(String email) async {
    try {
      print('🔍 Checking if email exists: $email');

      final emailLower = email.trim().toLowerCase();

      // Check in global users collection first
      final globalQuery = await _firestore
          .collection('users')
          .where('email', isEqualTo: emailLower)
          .limit(1)
          .get();

      if (globalQuery.docs.isNotEmpty) {
        print('❌ Email found in global users collection');
        return true;
      }

      // Also check authEmail field (for phone users who might have generated emails)
      final authEmailQuery = await _firestore
          .collection('users')
          .where('authEmail', isEqualTo: emailLower)
          .limit(1)
          .get();

      if (authEmailQuery.docs.isNotEmpty) {
        print('❌ Email found in authEmail field');
        return true;
      }

      // Check in current branch's mobileUsers collection
      if (branchId.isNotEmpty) {
        final branchQuery = await _firestore
            .collection('branches')
            .doc(branchId)
            .collection('mobileUsers')
            .where('email', isEqualTo: emailLower)
            .limit(1)
            .get();

        if (branchQuery.docs.isNotEmpty) {
          print('❌ Email found in branch mobileUsers collection');
          return true;
        }
      }

      print('✅ Email is available');
      return false;
    } catch (e) {
      print('❌ Error checking email existence: $e');
      // In case of error, don't block the user
      return false;
    }
  }



  // Save user data to Firestore
  Future<void> _saveUserData(User user) async {
    final userData = {
      'uid': user.uid,
      'name': _nameController.text.trim(),
      'email': _emailController.text.isNotEmpty ? _emailController.text.trim() : user.email,
      'phone': _phoneController.text.trim(),
      'loginMethod': _emailController.text.isNotEmpty ? 'email' : 'phone',
      'emailVerified': _emailVerified,
      'phoneVerified': _phoneVerified,
      'createdAt': FieldValue.serverTimestamp(),
      'branchId': branchId,
      'locationData': widget.locationData,
      'role': 'customer',
      'status': 'active',
      'authEmail': user.email,
    };

    // Save to branch-specific mobileUsers collection
    await _firestore
        .collection('branches')
        .doc(branchId)
        .collection('mobileUsers')
        .doc(user.uid)
        .set(userData);

    // Also save to global users collection
    await _firestore
        .collection('users')
        .doc(user.uid)
        .set(userData);

    // Create eBalance document with initial values
    final eBalanceData = {
      'main_balance': 0,
      'percent_balance': 0,
      'lastUpdated': FieldValue.serverTimestamp(),
    };

    await _firestore
        .collection('branches')
        .doc(branchId)
        .collection('mobileUsers')
        .doc(user.uid)
        .collection('user_eBalance')
        .doc('balance')
        .set(eBalanceData);

    print('User data and eBalance created successfully');
  }



  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Account'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildMethodToggle(),
              const SizedBox(height: 16),
              _buildNameField(),
              const SizedBox(height: 16),
              _buildEmailField(),
              const SizedBox(height: 16),
              _buildPhoneField(),
              const SizedBox(height: 16),
              _buildPasswordFields(),
              const SizedBox(height: 16),
              _buildOTPSection(),
              const SizedBox(height: 24),
              _buildSignupButton(),
              const SizedBox(height: 16),
              _buildStatusCard(),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildMethodToggle() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.phone, color: Colors.blue.shade600),
                const SizedBox(width: 8),
                const Text(
                  'Phone verification required for signup',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'You can login with either phone or email after signup',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildNameField() {
  return TextFormField(
    controller: _nameController,
    decoration: const InputDecoration(
      labelText: 'Full Name *',
      border: OutlineInputBorder(),
      prefixIcon: Icon(Icons.person),
    ),
    validator: (value) => value?.isEmpty == true ? 'Name is required' : null,
  );
}

  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailController,
      decoration: InputDecoration(
        labelText: 'Email Address (optional)',
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.email),
        suffixIcon: _emailVerified
            ? const Icon(Icons.check_circle, color: Colors.green)
            : null,
        errorText: _emailError,
        helperText: 'For login convenience and notifications',
      ),
      keyboardType: TextInputType.emailAddress,
      onChanged: _validateEmail,
      validator: (value) => _emailError, // Only show format errors, not required
    );
  }


  Widget _buildPhoneField() {
    return TextFormField(
      controller: _phoneController,
      decoration: InputDecoration(
        labelText: 'Phone Number *',
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.phone),
        suffixIcon: _phoneVerified
            ? const Icon(Icons.check_circle, color: Colors.green)
            : null,
        errorText: _phoneError,
        helperText: 'Include country code (e.g., +1234567890)',
      ),
      keyboardType: TextInputType.phone,
      onChanged: _validatePhone,
      validator: (value) => value?.isEmpty == true ? 'Phone is required' : _phoneError,
    );
  }


  Widget _buildPasswordFields() {
    return Column(
      children: [
        TextFormField(
          controller: _passwordController,
          decoration: InputDecoration(
            labelText: 'Password *',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.lock),
            suffixIcon: IconButton(
              icon: Icon(
                _showPassword ? Icons.visibility : Icons.visibility_off,
                color: Colors.grey,
              ),
              onPressed: () {
                setState(() {
                  _showPassword = !_showPassword;
                });
              },
            ),
            helperText: 'Minimum 6 characters',
          ),
          obscureText: !_showPassword,
          validator: _validatePassword,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _confirmPasswordController,
          decoration: InputDecoration(
            labelText: 'Confirm Password *',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(
                _showConfirmPassword ? Icons.visibility : Icons.visibility_off,
                color: Colors.grey,
              ),
              onPressed: () {
                setState(() {
                  _showConfirmPassword = !_showConfirmPassword;
                });
              },
            ),
          ),
          obscureText: !_showConfirmPassword,
          validator: (value) {
            if (value?.isEmpty == true) return 'Please confirm your password';
            if (value != _passwordController.text) return 'Passwords do not match';
            return null;
          },
        ),
      ],
    );
  }



  String? _validatePassword(String? value) {
    if (value?.isEmpty == true) return 'Password is required';
    if (value!.length < 6) return 'Password must be at least 6 characters';
    return null;
  }


  Widget _buildOTPSection() {
    return Column(
      children: [
        if (!_otpSent)
          ElevatedButton(
            onPressed: _phoneVerified && !_isLoading ? _sendOTP : null,
            child: _isLoading
                ? const CircularProgressIndicator()
                : const Text('Send OTP'),
          ),
        if (_otpSent) ...[
          TextFormField(
            controller: _otpController,
            decoration: const InputDecoration(
              labelText: 'Enter OTP *',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.security),
            ),
            keyboardType: TextInputType.number,
            maxLength: 6,
            onChanged: (value) {
              if (value.length == 6) _verifyOTP();
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                onPressed: _sendOTP,
                child: const Text('Resend OTP'),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: _otpController.text.length == 6 ? _verifyOTP : null,
                child: const Text('Verify'),
              ),
            ],
          ),
        ],
      ],
    );
  }


Widget _buildSignupButton() {
  return ElevatedButton(
    onPressed: _canCompleteSignup() && !_isLoading ? _completeSignup : null,
    style: ElevatedButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 16),
    ),
    child: _isLoading
        ? const CircularProgressIndicator()
        : const Text('Create Account', style: TextStyle(fontSize: 16)),
  );
}

  Widget _buildStatusCard() {
    return Card(
      color: Colors.grey[50],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _buildStatusRow('Phone verified', _phoneVerified),
            _buildStatusRow('Password set', _passwordController.text.length >= 6),
            if (_emailController.text.isNotEmpty)
              _buildStatusRow('Email added', _emailVerified),
          ],
        ),
      ),
    );
  }




  Widget _buildStatusRow(String label, bool verified) {
    return Row(
      children: [
        Icon(
          verified ? Icons.check_circle : Icons.radio_button_unchecked,
          color: verified ? Colors.green : Colors.grey,
          size: 16,
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: verified ? Colors.green : Colors.grey,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
