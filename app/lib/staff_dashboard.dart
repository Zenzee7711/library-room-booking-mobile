import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:room_booking_app/logout_function.dart';
import 'package:room_booking_app/staff_history.dart';
import 'package:room_booking_app/staff_browsing.dart';
import 'package:room_booking_app/config/api_config.dart';

class StaffDashboard extends StatefulWidget {
  const StaffDashboard({super.key});

  @override
  State<StaffDashboard> createState() => _StaffDashboardState();
}

class _StaffDashboardState extends State<StaffDashboard> {
  // Brand colors (match your app)
  static const kNavy = Color(0xFF003366);
  static const kGreen = Color(0xFF1FA22A);
  static const kRed = Color(0xFFDA351C);
  static const kGreyBg = Color(0xFFD9D9D9);

  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  String _staffName = '';
  String? _jwt;
  bool _loading = false;
  late final String _todayYMD;

  // live counts
  int _countAvailable = 0;
  int _countPending = 0;
  int _countReserved = 0;
  int _countDisabled = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _todayYMD =
        "${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    _jwt = await _secure.read(key: 'jwt');
    await _fetchMe();
    await _fetchSummary();
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
          if (mounted && name.isNotEmpty) setState(() => _staffName = name);
        }
      }
    } catch (_) {
      /* ignore */
    }
  }

  Future<void> _fetchSummary() async {
    setState(() => _loading = true);
    try {
      final url = Uri.parse(
        '${ApiConfig.baseUrl}/common/rooms/availability?date=$_todayYMD',
      );
      final resp = await http
          .get(url, headers: _authHeaders())
          .timeout(const Duration(seconds: 12));

      if (resp.statusCode != 200) {
        _snack(resp.body.isNotEmpty ? resp.body : 'Failed to load dashboard');
        _resetCounts();
        return;
      }

      final data = jsonDecode(resp.body);
      if (data is! Map || data['ok'] != true || data['rooms'] is! List) {
        _snack('Invalid availability response');
        _resetCounts();
        return;
      }

      int available = 0;
      int pending = 0;
      int reserved = 0;
      int disabled = 0;

      for (final r in (data['rooms'] as List)) {
        final roomStatus = (r as Map)['room_status'] ?? 1;
        final statuses = (r['statuses'] as Map).cast<String, dynamic>();

        if (roomStatus == 0) {
          // Entire room disabled => every slot is disabled
          disabled += statuses.length;
          continue;
        }

        for (final v in statuses.values) {
          final s = (v ?? '').toString();
          if (s == 'available') {
            available++;
          } else if (s == 'pending') {
            pending++;
          } else if (s == 'reserved') {
            reserved++;
          }
          // 'passed' is ignored for dashboard counts
        }
      }

      if (mounted) {
        setState(() {
          _countAvailable = available;
          _countPending = pending;
          _countReserved = reserved;
          _countDisabled = disabled;
        });
      }
    } on TimeoutException {
      _snack('Timeout while loading dashboard');
      _resetCounts();
    } catch (e) {
      _snack('Network error: $e');
      _resetCounts();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _resetCounts() {
    if (!mounted) return;
    setState(() {
      _countAvailable = 0;
      _countPending = 0;
      _countReserved = 0;
      _countDisabled = 0;
    });
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // Status card with highlighted border (same as lecturer)
  Widget _buildStatusCard({
    required String title,
    required int count,
    required Color color,
  }) {
    final hasItems = count > 0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        boxShadow: hasItems
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.15),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Card(
        color: Colors.white,
        elevation: 6,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
          side: BorderSide(color: color, width: hasItems ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: _loading ? null : _fetchSummary, // tap to refresh
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '$count',
                style: const TextStyle(
                  color: kNavy,
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final headerHeight = MediaQuery.of(context).size.height * 0.26;

    return Scaffold(
      backgroundColor: kGreyBg,

      // Bottom Nav (Back / Home+Refresh / Calendar)
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
                onPressed: () async {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('You are already on the Home page'),
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
                  if (!_loading) await _fetchSummary(); // force refresh
                },
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
                icon: const Icon(
                  Icons.calendar_today,
                  color: Colors.white,
                  size: 28,
                ),
                onPressed: () {
                  // standard bottom nav: go to staff history
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const StaffHistory()),
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
              color: kNavy,
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
                      // "Hi" bold, name normal (like Lecturer)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RichText(
                            text: TextSpan(
                              children: [
                                const TextSpan(
                                  text: 'Hi',
                                  style: TextStyle(
                                    fontSize: 30,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                TextSpan(
                                  text:
                                      ', ${_staffName.isNotEmpty ? _staffName : 'Staff'}',
                                  style: const TextStyle(
                                    fontSize: 29,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Text(
                            "Staff's Dashboard",
                            style: TextStyle(fontSize: 26, color: Colors.white),
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
                const Spacer(),
                Center(
                  child: Text(
                    "Dashboard shows today's room slot summary.",
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),

          const SizedBox(height: 35),

          // Status Grid
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 1, 14, 8),
                child: GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1.05,
                  children: [
                    _buildStatusCard(
                      title: 'Available',
                      count: _countAvailable,
                      color: kGreen,
                    ),
                    _buildStatusCard(
                      title: 'Pending',
                      count: _countPending,
                      color: Colors.orange,
                    ),
                    _buildStatusCard(
                      title: 'Reserved',
                      count: _countReserved,
                      color: Colors.blue,
                    ),
                    _buildStatusCard(
                      title: 'Disabled',
                      count: _countDisabled,
                      color: kRed,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
