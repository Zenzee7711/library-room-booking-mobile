import 'package:flutter/material.dart';
import 'package:room_booking_app/pages/welcome_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RoomBookingApp());
}

class RoomBookingApp extends StatelessWidget {
  const RoomBookingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Library Room Booking',
      debugShowCheckedModeBanner: false,
      home: WelcomePage(),
    );
  }
}
