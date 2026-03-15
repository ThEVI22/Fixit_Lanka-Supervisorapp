import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';

import 'screens/supervisor_login_screen.dart';
import 'screens/supervisor_home_screen.dart';
import 'screens/supervisor_job_details_screen.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const SupervisorApp());
}

class SupervisorApp extends StatelessWidget {
  const SupervisorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fixit Supervisor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.white,
        useMaterial3: true,
        textTheme: GoogleFonts.poppinsTextTheme(),
        appBarTheme: const AppBarTheme(
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          backgroundColor: Colors.white,
        ),
      ),
      home: const SupervisorLoginScreen(),
      routes: {
        '/supervisor-home': (context) => const SupervisorHomeScreen(),
        '/supervisor-job-details': (context) => const SupervisorJobDetailsScreen(),
        
      },
    );
  }
}