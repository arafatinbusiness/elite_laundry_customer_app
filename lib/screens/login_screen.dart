import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:email_validator/email_validator.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _auth = FirebaseAuth.instance;
  final _emailPhoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _otpController = TextEditingController();

  bool _isLoading = false;
  bool _isPhoneLogin = false;
  bool _otpSent = false;
  bool _showPassword = false;
  String? _verificationId;

  @override
  void dispose() {
    _emailPhoneController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  // Improved phone number normalization
  String _normalizePhoneNumber(String input) {
    // Remove all spaces, dashes, parentheses
    String normalized = input.replaceAll(RegExp(r'[\s\-\(\)]'), '');

    // If it doesn't start with +, add it
    if (!normalized.startsWith('+')) {
      normalized = '+$normalized';
    }

    return normalized;
  }

  void _detectLoginType(String input) {
    setState(() {
      // Check if it's a valid email format
      if (EmailValidator.validate(input)) {
        _isPhoneLogin = false;
      } else {
        // If it contains digits and possibly starts with + or has length >= 10, treat as phone
        _isPhoneLogin = input.contains(RegExp(r'\d')) &&
            (input.startsWith('+') || input.length >= 10);
      }
    });
    print('LOGIN: Input "$input" detected as ${_isPhoneLogin ? "phone" : "email"}');
  }

  Future<void> _sendOTP() async {
    setState(() => _isLoading = true);
    try {
      final normalizedPhone = _normalizePhoneNumber(_emailPhoneController.text.trim());

      await _auth.verifyPhoneNumber(
        phoneNumber: normalizedPhone,
        verificationCompleted: (PhoneAuthCredential credential) async {
          await _auth.signInWithCredential(credential);
          Navigator.pushReplacementNamed(context, '/home');
        },
        verificationFailed: (FirebaseAuthException e) {
          _showError('Phone verification failed: ${e.message}');
        },
        codeSent: (String verificationId, int? resendToken) {
          setState(() {
            _verificationId = verificationId;
            _otpSent = true;
          });
          _showSuccess('OTP sent to $normalizedPhone');
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      _showError('Failed to send OTP: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final inputValue = _emailPhoneController.text.trim();
    print('LOGIN: Starting login process');
    print('LOGIN: Input: $inputValue');
    print('LOGIN: Is phone login: $_isPhoneLogin');
    print('LOGIN: Password length: ${_passwordController.text.length}');

    try {
      if (_isPhoneLogin) {
        final normalizedPhone = _normalizePhoneNumber(inputValue);
        print('LOGIN: Normalized phone: $normalizedPhone');
        print('LOGIN: Phone login - querying Firestore for phone: $normalizedPhone');

        // Query Firestore to find user by phone number
        QuerySnapshot<Map<String, dynamic>> querySnapshot = await FirebaseFirestore.instance
            .collection('users')
            .where('phone', isEqualTo: normalizedPhone)
            .limit(1)
            .get();

        print('LOGIN: Firestore query completed');
        print('LOGIN: Found ${querySnapshot.docs.length} documents');

        if (querySnapshot.docs.isEmpty) {
          print('LOGIN: No user found with phone: $normalizedPhone');

          // Try alternative phone formats
          final alternativeFormats = [
            inputValue, // Original input
            inputValue.startsWith('+') ? inputValue.substring(1) : '+$inputValue',
            inputValue.replaceAll(RegExp(r'[^\d]'), ''), // Only digits
          ];

          print('LOGIN: Trying alternative phone formats: $alternativeFormats');

          bool foundUser = false;
          for (String altPhone in alternativeFormats) {
            if (altPhone != normalizedPhone) {
              final altQuery = await FirebaseFirestore.instance
                  .collection('users')
                  .where('phone', isEqualTo: altPhone)
                  .limit(1)
                  .get();

              if (altQuery.docs.isNotEmpty) {
                querySnapshot = altQuery;
                foundUser = true;
                print('LOGIN: Found user with alternative format: $altPhone');
                break;
              }
            }
          }

          if (!foundUser) {
            _showError('No account found with this phone number');
            return;
          }
        }

        final userData = querySnapshot.docs.first.data();
        print('LOGIN: User data found:');
        print('LOGIN: - UID: ${userData['uid']}');
        print('LOGIN: - Name: ${userData['name']}');
        print('LOGIN: - Email: ${userData['email']}');
        print('LOGIN: - Phone: ${userData['phone']}');
        print('LOGIN: - AuthEmail: ${userData['authEmail']}');
        print('LOGIN: - LoginMethod: ${userData['loginMethod']}');

        // Use authEmail for Firebase Auth login
        final authEmail = userData['authEmail'];
        if (authEmail == null) {
          print('LOGIN ERROR: No authEmail found for user');
          _showError('Account setup incomplete. Please contact support.');
          return;
        }

        print('LOGIN: Using authEmail for Firebase Auth: $authEmail');

        await _auth.signInWithEmailAndPassword(
          email: authEmail,
          password: _passwordController.text.trim(),
        );

        print('LOGIN: Phone login successful');
      } else {
        print('LOGIN: Email login - direct authentication');
        print('LOGIN: Email: $inputValue');

        await _auth.signInWithEmailAndPassword(
          email: inputValue,
          password: _passwordController.text.trim(),
        );

        print('LOGIN: Email login successful');
      }

      Navigator.pushReplacementNamed(context, '/home');
    } catch (e) {
      print('LOGIN ERROR: $e');
      print('LOGIN ERROR TYPE: ${e.runtimeType}');

      if (e is FirebaseAuthException) {
        print('LOGIN ERROR CODE: ${e.code}');
        print('LOGIN ERROR MESSAGE: ${e.message}');

        // Provide more specific error messages
        String errorMessage;
        switch (e.code) {
          case 'user-not-found':
            errorMessage = 'No account found with this email';
            break;
          case 'wrong-password':
            errorMessage = 'Incorrect password';
            break;
          case 'invalid-email':
            errorMessage = 'Invalid email format';
            break;
          case 'user-disabled':
            errorMessage = 'This account has been disabled';
            break;
          case 'too-many-requests':
            errorMessage = 'Too many failed attempts. Please try again later';
            break;
          case 'invalid-credential':
            errorMessage = 'Invalid email or password';
            break;
          default:
            errorMessage = 'Login failed: ${e.message}';
        }
        _showError(errorMessage);
      } else {
        _showError('Login failed: Please check your credentials');
      }
    } finally {
      setState(() => _isLoading = false);
    }
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

  Future<void> _handleForgotPassword() async {
    final inputValue = _emailPhoneController.text.trim();
    
    if (inputValue.isEmpty) {
      _showError('Please enter your email or phone number first');
      return;
    }

    setState(() => _isLoading = true);

    try {
      String emailToReset;

      if (_isPhoneLogin) {
        // For phone login, we need to find the associated email
        final normalizedPhone = _normalizePhoneNumber(inputValue);
        
        // Query Firestore to find user by phone number
        QuerySnapshot<Map<String, dynamic>> querySnapshot = await FirebaseFirestore.instance
            .collection('users')
            .where('phone', isEqualTo: normalizedPhone)
            .limit(1)
            .get();

        if (querySnapshot.docs.isEmpty) {
          _showError('No account found with this phone number');
          return;
        }

        final userData = querySnapshot.docs.first.data();
        final authEmail = userData['authEmail'];
        
        if (authEmail == null) {
          _showError('Account setup incomplete. Please contact support.');
          return;
        }

        emailToReset = authEmail;
      } else {
        // For email login, use the entered email directly
        if (!EmailValidator.validate(inputValue)) {
          _showError('Please enter a valid email address');
          return;
        }
        emailToReset = inputValue;
      }

      // Send password reset email
      await _auth.sendPasswordResetEmail(email: emailToReset);
      
      _showSuccess('Password reset email sent to $emailToReset');
      
    } catch (e) {
      print('PASSWORD RESET ERROR: $e');
      
      if (e is FirebaseAuthException) {
        switch (e.code) {
          case 'user-not-found':
            _showError('No account found with this email');
            break;
          case 'invalid-email':
            _showError('Invalid email format');
            break;
          default:
            _showError('Failed to send password reset email: ${e.message}');
        }
      } else {
        _showError('Failed to send password reset email. Please try again.');
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign In'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),

              // Login type indicator
              if (_emailPhoneController.text.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: _isPhoneLogin ? Colors.blue.shade50 : Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _isPhoneLogin ? Colors.blue.shade200 : Colors.green.shade200,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isPhoneLogin ? Icons.phone : Icons.email,
                        color: _isPhoneLogin ? Colors.blue : Colors.green,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Detected as ${_isPhoneLogin ? "phone" : "email"} login',
                        style: TextStyle(
                          color: _isPhoneLogin ? Colors.blue.shade700 : Colors.green.shade700,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

              // Email/Phone field
              TextFormField(
                controller: _emailPhoneController,
                decoration: InputDecoration(
                  labelText: 'Email or Phone Number',
                  border: const OutlineInputBorder(),
                  prefixIcon: Icon(_isPhoneLogin ? Icons.phone : Icons.email),
                  helperText: _isPhoneLogin
                      ? 'Enter phone with country code (e.g., +8801842701601)'
                      : 'Enter your email address',
                ),
                keyboardType: _isPhoneLogin ? TextInputType.phone : TextInputType.emailAddress,
                onChanged: _detectLoginType,
                validator: (value) => value?.isEmpty == true ? 'This field is required' : null,
              ),

              const SizedBox(height: 16),

              // Password field
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Password',
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
                ),
                obscureText: !_showPassword,
                validator: (value) => value?.isEmpty == true ? 'Password is required' : null,
              ),

              // Forgot password link
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _handleForgotPassword,
                  child: const Text('Forgot Password?'),
                ),
              ),

              const SizedBox(height: 24),

              // Login button
              ElevatedButton(
                onPressed: !_isLoading ? _login : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text('Sign In', style: TextStyle(fontSize: 16)),
              ),

              const SizedBox(height: 16),

              // Sign up link
              TextButton(
                onPressed: () => Navigator.pushNamed(context, '/select-location'),
                child: const Text("Don't have an account? Sign Up"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
