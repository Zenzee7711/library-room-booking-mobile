import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:room_booking_app/logout_function.dart';
import 'package:room_booking_app/staff_browsing.dart';
import 'staff_dashboard.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:room_booking_app/config/api_config.dart';

class StaffHistory extends StatefulWidget {
  const StaffHistory({super.key});

  @override
  State<StaffHistory> createState() => _StaffHistoryState();
}

class _StaffHistoryState extends State<StaffHistory>
    with SingleTickerProviderStateMixin {
  // ───────── config / deps ─────────
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  late TabController _tabController;

  String _firstName = 'Staff';
  String? _jwt;

  bool _loadingPending = false;
  bool _loadingHistory = false;

  // data lists
  List<Map<String, dynamic>> _pending = []; // all Waiting
  List<Map<String, dynamic>> _history = []; // all Approved/Rejected

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _bootstrap();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    _jwt = await _secure.read(key: 'jwt');
    await _fetchMe();
    await Future.wait([_fetchPending(), _fetchHistory()]);
  }

  Map<String, String> _authHeaders() {
    final h = <String, String>{'Content-Type': 'application/json'};
    if (_jwt != null && _jwt!.isNotEmpty) h['Authorization'] = 'Bearer $_jwt';
    return h;
  }

  Future<void> _fetchMe() async {
    try {
      final resp = await http
          .get(
            Uri.parse('${ApiConfig.baseUrl}/common/user_auth'),
            headers: _authHeaders(),
          )
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data is Map && data['ok'] == true && data['user'] is Map) {
          final u = data['user'] as Map;
          final first = (u['first_name'] ?? '').toString().trim();
          if (mounted && first.isNotEmpty) setState(() => _firstName = first);
        }
      }
    } catch (_) {}
  }

  // date helpers
  String _formatYMD(String ymd) {
    try {
      final d = DateTime.parse(ymd);
      const w = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      const m = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      final wd = w[(d.weekday + 6) % 7];
      final mo = m[d.month - 1];
      return '$wd, $mo ${d.day}';
    } catch (_) {
      return ymd;
    }
  }

  // ───────── API calls ─────────

  // ALL pending student bookings (Waiting)
  Future<void> _fetchPending() async {
    setState(() => _loadingPending = true);
    try {
      final resp = await http
          .get(
            Uri.parse('${ApiConfig.baseUrl}/staff/bookings/pending'),
            headers: _authHeaders(),
          )
          .timeout(const Duration(seconds: 12));

      if (resp.statusCode != 200) {
        _snack(resp.body.isNotEmpty ? resp.body : 'Failed to load pending');
        if (mounted) setState(() => _pending = []);
        return;
      }

      final data = jsonDecode(resp.body);
      if (data is! Map || data['ok'] != true || data['bookings'] is! List) {
        _snack('Invalid pending response');
        if (mounted) setState(() => _pending = []);
        return;
      }

      final rows = (data['bookings'] as List);
      final out = <Map<String, dynamic>>[];

      for (final b in rows) {
        final m = b as Map;
        final roomName = (m['room_name'] ?? 'Room').toString();
        final dateYMD = (m['booking_date'] ?? '').toString();
        final start = (m['start_time'] ?? '').toString();
        final end = (m['end_time'] ?? '').toString();
        final student = (m['booked_by_name'] ?? '').toString();

        out.add({
          'booking_id': m['booking_id'],
          'room': roomName,
          'date': _formatYMD(dateYMD),
          'time': '${start.substring(0, 5)} - ${end.substring(0, 5)}',
          'status': 0, // 0 used for pending/rejected in your UI
          'approver': '', // empty => pending
          'booked_by': student,
          '_order_id': (m['booking_id'] ?? 0) as int,
        });
      }

      // newest first by id
      out.sort(
        (a, b) => (b['_order_id'] as int).compareTo(a['_order_id'] as int),
      );

      if (mounted) setState(() => _pending = out);
    } on TimeoutException {
      _snack('Timeout while loading pending');
    } catch (e) {
      _snack('Network error: $e');
    } finally {
      if (mounted) setState(() => _loadingPending = false);
    }
  }

  // ALL historical bookings (Approved/Rejected) with full info
  Future<void> _fetchHistory() async {
    setState(() => _loadingHistory = true);
    try {
      final resp = await http
          .get(
            Uri.parse('${ApiConfig.baseUrl}/staff/bookings/history'),
            headers: _authHeaders(),
          )
          .timeout(const Duration(seconds: 12));

      if (resp.statusCode != 200) {
        _snack(resp.body.isNotEmpty ? resp.body : 'Failed to load history');
        if (mounted) setState(() => _history = []);
        return;
      }

      final data = jsonDecode(resp.body);
      if (data is! Map || data['ok'] != true || data['bookings'] is! List) {
        _snack('Invalid history response');
        if (mounted) setState(() => _history = []);
        return;
      }

      final rows = (data['bookings'] as List);
      final out = <Map<String, dynamic>>[];

      for (final b in rows) {
        final m = b as Map;
        final statusStr = (m['booking_status'] ?? '')
            .toString(); // Approved | Rejected
        final isApproved = statusStr == 'Approved';

        final roomName = (m['room_name'] ?? 'Room').toString();
        final dateYMD = (m['booking_date'] ?? '').toString();
        final start = (m['start_time'] ?? '').toString();
        final end = (m['end_time'] ?? '').toString();
        final approver = (m['approver_name'] ?? '').toString();
        final student = (m['booked_by_name'] ?? '').toString();
        final reason = (m['reject_reason'] ?? '').toString();

        out.add({
          'booking_id': m['booking_id'],
          'room': roomName,
          'date': _formatYMD(dateYMD),
          'time': '${start.substring(0, 5)} - ${end.substring(0, 5)}',
          'status': isApproved ? 1 : 0, // 1 approved, 0 rejected
          'approver': approver,
          'booked_by': student,
          'reason': reason,
          '_order_id': (m['booking_id'] ?? 0) as int,
        });
      }

      // newest first by id
      out.sort(
        (a, b) => (b['_order_id'] as int).compareTo(a['_order_id'] as int),
      );

      if (mounted) setState(() => _history = out);
    } on TimeoutException {
      _snack('Timeout while loading history');
    } catch (e) {
      _snack('Network error: $e');
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  // ───────── UI helpers ─────────
  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Widget _buildEmptyState(String title) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[400]),
        const SizedBox(height: 16),
        Text(
          '$title is empty',
          style: TextStyle(fontSize: 18, color: Colors.grey[600]),
        ),
        const SizedBox(height: 8),
        Text(
          'No ${title.toLowerCase()} bookings found',
          style: TextStyle(color: Colors.grey[500]),
        ),
      ],
    ),
  );

  Widget _buildBookingCard(Map<String, dynamic> b) {
    final int status = b['status'] as int;
    final bool isPending = status == 0 && (b['approver'] as String).isEmpty;

    String statusText;
    Color statusColor;
    IconData statusIcon;

    if (isPending) {
      statusText = 'Pending Approval';
      statusColor = Colors.orange;
      statusIcon = Icons.circle_outlined;
    } else if (status == 0) {
      statusText = 'Rejected';
      statusColor = Colors.red;
      statusIcon = Icons.close;
    } else {
      statusText = 'Approved';
      statusColor = const Color(0xFF1FA22A);
      statusIcon = Icons.check;
    }

    return Card(
      color: Colors.white,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: statusColor, width: 2),
      ),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Session in Room
            RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 16, color: Colors.black),
                children: [
                  const TextSpan(text: 'Session in '),
                  TextSpan(
                    text: b['room'],
                    style: const TextStyle(color: Colors.orange),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Date & Time
            Row(
              children: [
                const Icon(Icons.calendar_month_outlined, size: 20),
                const SizedBox(width: 6),
                Text(b['date'], style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 20),
                const Icon(Icons.access_time, size: 18),
                const SizedBox(width: 6),
                Text(b['time'], style: const TextStyle(fontSize: 14)),
              ],
            ),
            const SizedBox(height: 8),

            // Booked by
            Row(
              children: [
                const Icon(Icons.person_outline, size: 20),
                const SizedBox(width: 6),
                RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 14, color: Colors.black),
                    children: [
                      const TextSpan(text: 'Booked by '),
                      TextSpan(
                        text: (b['booked_by'] ?? '').toString(),
                        style: const TextStyle(color: Colors.orange),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),

            // Status line
            Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 20),
                const SizedBox(width: 6),
                RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 14, color: Colors.black),
                    children: [
                      TextSpan(text: statusText),
                      if (!isPending &&
                          (b['approver'] as String).isNotEmpty) ...[
                        const TextSpan(text: ' by '),
                        TextSpan(
                          text: (b['approver'] ?? '').toString(),
                          style: const TextStyle(color: Colors.orange),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),

            // Reason for rejected ones
            if (status == 0 &&
                (b['approver'] as String).isNotEmpty &&
                (b['reason'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 20,
                    color: Colors.redAccent,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Reason: ${b['reason']}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ───────── MAIN BUILD ─────────
  @override
  Widget build(BuildContext context) {
    final headerHeight = MediaQuery.of(context).size.height * 0.24;

    return Scaffold(
      backgroundColor: const Color(0xFFD9D9D9),
      extendBody: true,

      // Bottom Nav
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          height: 56,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 1),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                onPressed: () => Navigator.maybePop(context),
              ),
              IconButton(
                icon: const Icon(
                  Icons.home_filled,
                  color: Colors.white,
                  size: 28,
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const StaffDashboard()),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.search, color: Colors.white, size: 28),
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const StaffBrowsing()),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.calendar_today, color: Colors.white),
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text(
                        'You are already on the Booking page',
                      ),
                      duration: const Duration(milliseconds: 1200),
                      behavior: SnackBarBehavior.floating,
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),

      // Body
      body: Column(
        children: [
          // Header
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFF003366),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(30),
                bottomRight: Radius.circular(30),
              ),
              border: Border(bottom: BorderSide(color: Colors.black, width: 2)),
            ),
            width: double.infinity,
            height: headerHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 60),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 25),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Greeting (bold "Hi," only)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            TextSpan(
                              children: [
                                const TextSpan(
                                  text: 'Hi, ',
                                  style: TextStyle(
                                    fontSize: 28,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                TextSpan(
                                  text: _firstName,
                                  style: const TextStyle(
                                    fontSize: 28,
                                    color: Colors.white,
                                    fontWeight: FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Text(
                            'Bookings',
                            style: TextStyle(fontSize: 25, color: Colors.white),
                          ),
                        ],
                      ),
                      IconButton(
                        onPressed: () => showLogoutDialog(context),
                        icon: const Icon(
                          Icons.logout_rounded,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Tabs
                Padding(
                  padding: const EdgeInsets.only(left: 20.0),
                  child: SizedBox(
                    width: 185,
                    child: TabBar(
                      controller: _tabController,
                      labelColor: Colors.amber,
                      unselectedLabelColor: Colors.white70,
                      indicatorColor: Colors.amber,
                      indicatorSize: TabBarIndicatorSize.label,
                      dividerColor: Colors.transparent,
                      labelStyle: const TextStyle(fontSize: 20),
                      labelPadding: const EdgeInsets.symmetric(horizontal: 0),
                      tabs: const [
                        Tab(text: 'Pending'),
                        Tab(text: 'History'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Tabs
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _loadingPending
                    ? const Center(child: CircularProgressIndicator())
                    : (_pending.isEmpty
                          ? _buildEmptyState('Pending')
                          : ListView.builder(
                              padding: const EdgeInsets.only(
                                top: 10,
                                bottom: 100,
                              ),
                              itemCount: _pending.length,
                              itemBuilder: (_, i) =>
                                  _buildBookingCard(_pending[i]),
                            )),
                _loadingHistory
                    ? const Center(child: CircularProgressIndicator())
                    : (_history.isEmpty
                          ? _buildEmptyState('History')
                          : ListView.builder(
                              padding: const EdgeInsets.only(
                                top: 10,
                                bottom: 100,
                              ),
                              itemCount: _history.length,
                              itemBuilder: (_, i) =>
                                  _buildBookingCard(_history[i]),
                            )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
