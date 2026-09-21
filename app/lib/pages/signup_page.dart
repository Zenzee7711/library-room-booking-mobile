import 'package:flutter/material.dart';
import 'signin_page.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:room_booking_app/config/api_config.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  // secure storage for JWT
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  bool _submitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _passController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Registers the account, stores the token the API returns, and moves on to
  /// the sign in screen.
  Future<void> _attemptSignUp() async {
    if (_submitting) return;

    final email = _emailController.text.trim();
    final first = _firstNameController.text.trim();
    final last = _lastNameController.text.trim();
    final pass = _passController.text;
    final confirm = _confirmController.text;

    if (email.isEmpty ||
        first.isEmpty ||
        last.isEmpty ||
        pass.isEmpty ||
        confirm.isEmpty) {
      _snack('Please fill in all fields');
      return;
    }
    if (pass != confirm) {
      _snack('Passwords do not match');
      return;
    }

    setState(() => _submitting = true);
    try {
      final resp = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/register/create'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email,
              'password': pass,
              'first_name': first,
              'last_name': last, // the API always registers a student
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        // The API signs the new account straight in, so keep the token.
        try {
          final data = jsonDecode(resp.body);
          final token = (data is Map ? data['token'] ?? '' : '').toString();
          if (token.isNotEmpty) {
            await _secure.write(key: 'jwt', value: token);
          }
        } catch (_) {
          // A non-JSON body is not fatal here: the account exists either way.
        }

        _snack('Registered successfully');
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const SignInPage()),
        );
        return;
      }

      _snack(_errorFrom(resp.body));
    } on TimeoutException {
      _snack('The server took too long to respond. Please try again.');
    } catch (e) {
      _snack('Network error: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// The API reports failures as { "error": ... }, but a proxy or a crash can
  /// return plain text, so fall back to the raw body.
  String _errorFrom(String body) {
    if (body.isEmpty) return 'Registration failed';
    try {
      final parsed = jsonDecode(body);
      if (parsed is Map && parsed['error'] != null) {
        return parsed['error'].toString();
      }
    } catch (_) {
      // Not JSON.
    }
    return body;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Container(
        width: size.width,
        height: size.height,
        color: Colors.white,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Header Text ───────────────────────────────
            Padding(
              padding: const EdgeInsets.only(top: 100, left: 30, bottom: 80),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        color: Color(0xFF0E2A5D),
                        fontSize: 49,
                        fontWeight: FontWeight.bold,
                      ),
                      children: const [
                        TextSpan(text: 'Sign '),
                        TextSpan(
                          text: 'Up',
                          style: TextStyle(
                            decoration: TextDecoration.underline,
                            decorationThickness: 1,
                          ),
                        ),
                        TextSpan(text: ','),
                      ],
                    ),
                  ),
                  const SizedBox(height: 15),
                  const Text(
                    'Keep pushing forward',
                    style: TextStyle(
                      color: Color(0xFF0E2A5D),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Create your student account',
                    style: TextStyle(
                      color: Color(0xFF0E2A5D),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            // ─── Form Section ──────────────────────────────
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0E2A5D), Color(0xFF1A4FA8)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(50),
                    topRight: Radius.circular(50),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 30,
                    vertical: 40,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(height: 20),

                        // Email
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.email_outlined),
                            hintText: 'Email',
                            filled: true,
                            fillColor: Colors.grey.shade300,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 18,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // First + Last Name (side by side)
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _firstNameController,
                                decoration: InputDecoration(
                                  prefixIcon: const Icon(Icons.person_outline),
                                  hintText: 'First Name',
                                  filled: true,
                                  fillColor: Colors.grey.shade300,
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 18,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(20),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _lastNameController,
                                decoration: InputDecoration(
                                  prefixIcon: const Icon(Icons.person_outline),
                                  hintText: 'Last Name',
                                  filled: true,
                                  fillColor: Colors.grey.shade300,
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 18,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(20),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Password
                        TextField(
                          controller: _passController,
                          obscureText: true,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.lock_outline),
                            hintText: 'Password',
                            filled: true,
                            fillColor: Colors.grey.shade300,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 18,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Confirm Password
                        TextField(
                          controller: _confirmController,
                          obscureText: true,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.lock_outline),
                            hintText: 'Confirm Password',
                            filled: true,
                            fillColor: Colors.grey.shade300,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 18,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),

                        // Sign Up Button
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF0E2A5D),
                            shadowColor: Colors.black,
                            elevation: 10,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 80,
                              vertical: 16,
                            ),
                          ),
                          onPressed: _submitting ? null : _attemptSignUp,
                          child: Text(
                            _submitting ? 'SIGNING UP...' : 'SIGN UP',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),

                        // Already have account?
                        GestureDetector(
                          onTap: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const SignInPage(),
                              ),
                            );
                          },
                          child: const Text.rich(
                            TextSpan(
                              text: "Already have an Account? ",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                              ),
                              children: [
                                TextSpan(
                                  text: "Sign In",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    decoration: TextDecoration.underline,
                                    decorationColor: Colors.white,
                                    decorationThickness: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
