import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:room_booking_app/logout_function.dart';
import 'package:room_booking_app/lecturer_browsing.dart';
import 'package:room_booking_app/lecturer_dashboard.dart';
import 'package:room_booking_app/config/api_config.dart';

class LecturerHistory extends StatefulWidget {
  const LecturerHistory({super.key});

  @override
  State<LecturerHistory> createState() => _LecturerHistoryState();
}

class _LecturerHistoryState extends State<LecturerHistory>
    with SingleTickerProviderStateMixin {
  // ─────────────────────────────────────────────────────────────
  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  late TabController _tabController;

  String username = '';

  // Data
  bool _loadingPending = false;
  bool _loadingHistory = false;
  List<Map<String, dynamic>> _pending = []; // Waiting
  List<Map<String, dynamic>> _history = []; // Approved / Rejected
  String? _jwt;

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
          final name = first;
          if (name.isNotEmpty && mounted) {
            setState(() => username = 'Aj.$name');
          }
        }
      }
    } catch (_) {}
  }

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

  // ─────────────────────────────────────────────────────────────
  // API: Pending (students' requests for this lecturer)
  Future<void> _fetchPending() async {
    setState(() => _loadingPending = true);
    try {
      final resp = await http
          .get(
            Uri.parse('${ApiConfig.baseUrl}/lecturer/bookings/pending'),
            headers: _authHeaders(),
          )
          .timeout(const Duration(seconds: 12));

      if (resp.statusCode != 200) {
        _snack(
          resp.body.isNotEmpty ? resp.body : 'Failed to load pending bookings',
        );
        setState(() => _pending = []);
        return;
      }

      final data = jsonDecode(resp.body);
      if (data is! Map || data['ok'] != true || data['bookings'] is! List) {
        _snack('Invalid pending response');
        setState(() => _pending = []);
        return;
      }

      final List rows = data['bookings'];
      final List<Map<String, dynamic>> out = [];

      for (final b in rows) {
        final roomName = (b['room_name'] ?? 'Room').toString();
        final dateYMD = (b['booking_date'] ?? '').toString();
        final start = (b['start_time'] ?? '').toString();
        final end = (b['end_time'] ?? '').toString();
        final bookedBy = (b['booked_by_name'] ?? '').toString();
        final bookingId = b['booking_id'];
        // status is Waiting for pending
        out.add({
          'booking_id': bookingId,
          'room': roomName,
          'date': _formatYMD(dateYMD),
          'time': '${start.substring(0, 5)} - ${end.substring(0, 5)}',
          'status':
              0, // 0 => pending/rejected in your UI; we'll treat no approver = pending
          'approver': '', // empty => pending
          'booked_by': bookedBy,
          '_order_date': dateYMD,
          '_order_slot': (b['slot_id'] ?? 0) as int,
        });
      }

      // newest first
      out.sort((a, b) {
        final ad =
            DateTime.tryParse(a['_order_date'] ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bd =
            DateTime.tryParse(b['_order_date'] ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final c = bd.compareTo(ad);
        if (c != 0) return c;
        return ((b['_order_slot'] ?? 0) as int).compareTo(
          (a['_order_slot'] ?? 0) as int,
        );
      });

      if (mounted) setState(() => _pending = out);
    } on TimeoutException {
      _snack('Timeout while loading pending');
    } catch (e) {
      _snack('Network error: $e');
    } finally {
      if (mounted) setState(() => _loadingPending = false);
    }
  }

  // API: History (decisions made by this lecturer)
  Future<void> _fetchHistory() async {
    setState(() => _loadingHistory = true);
    try {
      final resp = await http
          .get(
            Uri.parse('${ApiConfig.baseUrl}/lecturer/bookings/history'),
            headers: _authHeaders(),
          )
          .timeout(const Duration(seconds: 12));

      if (resp.statusCode != 200) {
        _snack(resp.body.isNotEmpty ? resp.body : 'Failed to load history');
        setState(() => _history = []);
        return;
      }

      final data = jsonDecode(resp.body);
      if (data is! Map || data['ok'] != true || data['bookings'] is! List) {
        _snack('Invalid history response');
        setState(() => _history = []);
        return;
      }

      final List rows = data['bookings'];
      final List<Map<String, dynamic>> out = [];

      for (final b in rows) {
        final statusStr = (b['booking_status'] ?? '')
            .toString(); // 'Approved' | 'Rejected'
        final approved = statusStr == 'Approved';
        final roomName = (b['room_name'] ?? 'Room').toString();
        final dateYMD = (b['booking_date'] ?? '').toString();
        final start = (b['start_time'] ?? '').toString();
        final end = (b['end_time'] ?? '').toString();
        final approver = (b['approver_name'] ?? '').toString();
        final reason = (b['reject_reason'] ?? '').toString();
        final bookedBy = (b['booked_by_name'] ?? '').toString();

        out.add({
          'booking_id': b['booking_id'],
          'room': roomName,
          'date': _formatYMD(dateYMD),
          'time': '${start.substring(0, 5)} - ${end.substring(0, 5)}',
          'status': approved
              ? 1
              : 0, // 1 approved / 0 rejected (approver non-empty = history)
          'approver': approver,
          'booked_by': bookedBy,
          'reason': reason,
          '_order_date': dateYMD,
          '_order_slot': (b['slot_id'] ?? 0) as int,
        });
      }

      // newest first
      out.sort((a, b) {
        final ad =
            DateTime.tryParse(a['_order_date'] ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bd =
            DateTime.tryParse(b['_order_date'] ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final c = bd.compareTo(ad);
        if (c != 0) return c;
        return ((b['_order_slot'] ?? 0) as int).compareTo(
          (a['_order_slot'] ?? 0) as int,
        );
      });

      if (mounted) setState(() => _history = out);
    } on TimeoutException {
      _snack('Timeout while loading history');
    } catch (e) {
      _snack('Network error: $e');
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  // Approve / Reject
  Future<void> _approveBooking(Map<String, dynamic> booking) async {
    final id = booking['booking_id'];
    try {
      final resp = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/lecturer/bookings/$id/approve'),
            headers: _authHeaders(),
            body: jsonEncode({}),
          )
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        await _showApprovedDialog();
        // move item from pending -> history
        setState(() {
          _pending.removeWhere((e) => e['booking_id'] == id);
        });
        await _fetchHistory();
      } else {
        _snack(resp.body.isNotEmpty ? resp.body : 'Approve failed');
      }
    } catch (e) {
      _snack('Approve error: $e');
    }
  }

  Future<void> _rejectBooking(Map<String, dynamic> booking) async {
    final id = booking['booking_id'];
    final reasonController = TextEditingController();
    bool enabled = false;

    final bool? submit = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Reason for Rejection'),
          content: TextField(
            controller: reasonController,
            autofocus: true,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Reason',
              hintText: 'e.g., Room maintenance',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 18,
              ),
            ),
            onChanged: (t) => setDialog(() => enabled = t.trim().isNotEmpty),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: enabled ? () => Navigator.of(ctx).pop(true) : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF003366),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );

    if (submit == true) {
      try {
        final resp = await http
            .post(
              Uri.parse('${ApiConfig.baseUrl}/lecturer/bookings/$id/reject'),
              headers: _authHeaders(),
              body: jsonEncode({'reason': reasonController.text.trim()}),
            )
            .timeout(const Duration(seconds: 10));
        if (resp.statusCode == 200) {
          await _showRejectedDialog();
          setState(() {
            _pending.removeWhere((e) => e['booking_id'] == id);
          });
          await _fetchHistory();
        } else {
          _snack(resp.body.isNotEmpty ? resp.body : 'Reject failed');
        }
      } catch (e) {
        _snack('Reject error: $e');
      }
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // ─────────────────────────────────────────────────────────────
  // UI helpers (Card + Empty) keeps your layout, adds colored border
  Widget _buildBookingCard(
    Map<String, dynamic> b, {
    bool hideApproverName = false,
  }) {
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

            // Date + Time
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
            const SizedBox(height: 12),

            // Pending actions OR status line
            if (isPending) ...[
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _approveBooking(b),
                      icon: const Icon(
                        Icons.check,
                        size: 18,
                        color: Colors.white,
                      ),
                      label: const Text(
                        'Approve',
                        style: TextStyle(color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1FA22A),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        shape: const StadiumBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _rejectBooking(b),
                      icon: const Icon(
                        Icons.close,
                        size: 18,
                        color: Colors.white,
                      ),
                      label: const Text(
                        'Reject',
                        style: TextStyle(color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDA351C),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        shape: const StadiumBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  Icon(statusIcon, color: statusColor, size: 20),
                  const SizedBox(width: 6),
                  // Show "Approved" / "Rejected" only; omit "by <name>" if hideApproverName
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 14, color: Colors.black),
                      children: [
                        TextSpan(text: statusText),
                        if (!hideApproverName &&
                            (b['approver'] ?? '').toString().isNotEmpty) ...[
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
              if (status == 0 && (b['reason'] ?? '').toString().isNotEmpty) ...[
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
          ],
        ),
      ),
    );
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

  // Small status dialogs
  Future<void> _showApprovedDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        // Resolved now rather than inside the callback: by the time the timer
        // fires the dialog may already have been dismissed by hand.
        final navigator = Navigator.of(ctx, rootNavigator: true);
        Future.delayed(const Duration(milliseconds: 1200), () {
          if (navigator.canPop()) navigator.pop();
        });
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 40),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Padding(
            padding: EdgeInsets.fromLTRB(24, 28, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, size: 120, color: Color(0xFF1FA22A)),
                SizedBox(height: 14),
                Text(
                  'Booking Approved',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showRejectedDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        // Resolved now rather than inside the callback: by the time the timer
        // fires the dialog may already have been dismissed by hand.
        final navigator = Navigator.of(ctx, rootNavigator: true);
        Future.delayed(const Duration(milliseconds: 1200), () {
          if (navigator.canPop()) navigator.pop();
        });
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 40),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Padding(
            padding: EdgeInsets.fromLTRB(24, 28, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cancel, size: 120, color: Color(0xFFDA351C)),
                SizedBox(height: 14),
                Text(
                  'Booking Rejected',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────
  // BUILD
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
                  MaterialPageRoute(builder: (_) => const LecturerDashboard()),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.search, color: Colors.white, size: 28),
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const LecturerBrowsing()),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.calendar_today, color: Colors.white),
                onPressed: () {
                  // already here
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
          // Header and tabs
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
                      // Greeting + subtitle
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RichText(
                            text: TextSpan(
                              children: [
                                const TextSpan(
                                  text: 'Hi',
                                  style: TextStyle(
                                    fontSize: 28,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                TextSpan(
                                  text: ', $username',
                                  style: const TextStyle(
                                    fontSize: 28,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Text(
                            'Booking Requests',
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
                              itemBuilder: (_, i) => _buildBookingCard(
                                _history[i],
                                hideApproverName: true,
                              ),
                            )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
