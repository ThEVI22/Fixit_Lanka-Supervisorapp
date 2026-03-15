import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/custom_dialog.dart';

class SupervisorLoginScreen extends StatefulWidget {
  const SupervisorLoginScreen({super.key});

  @override
  State<SupervisorLoginScreen> createState() => _SupervisorLoginScreenState();
}

class _SupervisorLoginScreenState extends State<SupervisorLoginScreen> {
  final _idController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _idController.addListener(_clearError);
    _passwordController.addListener(_clearError);
  }

  void _clearError() {
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }
  }

  // --- CLEANED LOGIN LOGIC: SUPERVISOR ONLY ---
  Future<void> _handleLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final inputId = _idController.text.trim().toUpperCase();
    final inputSecret = _passwordController.text.trim();

    try {
      if (inputId.isEmpty || inputSecret.isEmpty) {
        throw 'Please fill in all fields.';
      }

      // --- 1. SUPERVISOR LOGIN (Teams Collection) ---
      final querySnapshot = await FirebaseFirestore.instance
          .collection('teams')
          .where('teamId', isEqualTo: inputId)
          .get();

      if (querySnapshot.docs.isEmpty) throw 'Invalid Team ID.';
      
      final teamDoc = querySnapshot.docs.first;
      final teamData = teamDoc.data();

      if (teamData['passcode'] != inputSecret) throw 'Incorrect Passcode.';

      // Authenticate Anonymously for Firebase Rules (Optional - proceeds even if failed)
      try {
        await FirebaseAuth.instance.signInAnonymously();
      } catch (e) {
        print("Warning: Firebase Auth failed. Uploads might fail if rules require auth. Error: $e");
      }

      // ✅ Session Persistence
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_role', 'Supervisor');
      await prefs.setString('team_doc_id', teamDoc.id);
      await prefs.setString('team_id', teamData['teamId']);
      await prefs.setBool('is_logged_in', true);

      if (mounted) {
        setState(() => _isLoading = false);
        
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => CustomDialog(
            icon: Icons.check_rounded,
            iconColor: Colors.green,
            iconContainerColor: Colors.green.withOpacity(0.1),
            title: "Login Successful",
            subtitle: "Welcome, Supervisor! Ready for oversight?",
            primaryActionText: "Let's Go",
            secondaryActionText: "", // Hide Cancel
            onPrimaryAction: () {
              Navigator.pop(context); // Close dialog
              Navigator.pushReplacementNamed(context, '/supervisor-home');
            },
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Stack(
          children: [
              // Background Image - Matched User App Style
              Positioned(
                top: 0, left: 0, right: 0,
                child: Image.asset(
                  'assets/supervisor_welcome_dark.png',
                  height: size.height * 0.5,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              // Main Content Area
              Positioned(
                top: size.height * 0.44,
                left: 0, right: 0, bottom: 0,
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(topLeft: Radius.circular(40), topRight: Radius.circular(40)),
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, -5))],
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 30, 24, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome to,',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.black.withOpacity(0.45),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Fixit Supervisor',
                          style: GoogleFonts.poppins(
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Manage teams, verify reports, and ensure quality control across all deployment zones.',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            height: 1.6,
                            color: Colors.black.withOpacity(0.65),
                          ),
                        ),
                        
                        const SizedBox(height: 30),
                        
                        // ERROR BANNER
                        if (_errorMessage != null) _buildErrorBanner(),

                        _buildTextField(
                          controller: _idController,
                          label: 'TEAM ID',
                          hint: 'T-0000',
                          icon: Icons.badge_outlined,
                        ),
                        const SizedBox(height: 20),
                        _buildTextField(
                          controller: _passwordController,
                          label: 'PASSCODE',
                          hint: '••••••',
                          icon: Icons.lock_outline,
                          isPassword: true,
                        ),
                        const SizedBox(height: 40),
                        
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              elevation: 5,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shadowColor: Colors.black45,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: _isLoading 
                              ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                              : Text('AUTHENTICATE', style: GoogleFonts.poppins(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 25),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        border: Border.all(color: const Color(0xFFFFCDD2)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(color: Color(0xFFFFCDD2), shape: BoxShape.circle),
            child: const Icon(Icons.priority_high_rounded, color: Color(0xFFD32F2F), size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Access Denied", style: GoogleFonts.poppins(color: const Color(0xFFD32F2F), fontWeight: FontWeight.bold, fontSize: 13)),
                Text(_errorMessage!, style: GoogleFonts.poppins(color: const Color(0xFFD32F2F), fontSize: 12)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _errorMessage = null),
            child: const Icon(Icons.close, color: Color(0xFFD32F2F), size: 18),
          )
        ],
      ),
    );
  }

  Widget _buildTextField({required TextEditingController controller, required String label, required String hint, required IconData icon, bool isPassword = false}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey[800], letterSpacing: 0.5)),
      const SizedBox(height: 10),
      Container(
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: TextField(
          controller: controller,
          obscureText: isPassword,
          keyboardType: isPassword ? TextInputType.visiblePassword : TextInputType.text,
          style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.poppins(color: Colors.grey[400]),
            prefixIcon: Icon(icon, size: 22, color: Colors.black87),
            filled: true, fillColor: Colors.transparent,
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: Colors.grey.shade200)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Colors.black, width: 1.5)),
            contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          ),
        ),
      ),
    ]);
  }
}
