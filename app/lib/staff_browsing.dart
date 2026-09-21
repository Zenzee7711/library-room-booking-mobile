import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:room_booking_app/staff_history.dart';
import 'package:room_booking_app/staff_room_management.dart';
import 'package:room_booking_app/logout_function.dart';
import 'package:room_booking_app/staff_dashboard.dart';
import 'package:room_booking_app/config/api_config.dart';

class StaffBrowsing extends StatefulWidget {
  const StaffBrowsing({super.key});

  @override
  State<StaffBrowsing> createState() => _StaffBrowsingState();
}

class _StaffBrowsingState extends State<StaffBrowsing> {
  // ---- config / deps ----
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  // ---- auth / user ----
  String? _jwt;
  String _staffFirstName = 'Staff';

  // ---- date / categories ----
  late final String _todayYMD;
  final List<String> categories = ['Study', 'Multimedia', 'Meeting'];
  String selectedCategory = 'Meeting';

  // ---- data ----
  List<String> timeSlots = [];
  Map<String, List<Map<String, dynamic>>> roomsByCategory = {
    'Study': [],
    'Multimedia': [],
    'Meeting': [],
  };

  bool _loading = false;

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
    await _fetchMe(); // show "Hi, <first>"
    await _fetchAvailability(); // initial data
  }

  Map<String, String> _authHeaders() {
    final h = <String, String>{'Content-Type': 'application/json'};
    if (_jwt != null && _jwt!.isNotEmpty) h['Authorization'] = 'Bearer $_jwt';
    return h;
  }

  // ───────────────────────────────────────────────────────────────
  // API: /common/user_auth (same as lecturer) → first name
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
          if (mounted && first.isNotEmpty) {
            setState(() => _staffFirstName = first);
          }
        }
      }
    } catch (_) {
      /* ignore */
    }
  }

  // ───────────────────────────────────────────────────────────────
  // API: /common/rooms/availability?date=YYYY-MM-DD (read-only)
  Future<void> _fetchAvailability() async {
    setState(() => _loading = true);
    try {
      final url = Uri.parse(
        '${ApiConfig.baseUrl}/common/rooms/availability?date=$_todayYMD',
      );
      final resp = await http
          .get(url, headers: _authHeaders())
          .timeout(const Duration(seconds: 12));

      if (resp.statusCode != 200) {
        _snack(resp.body.isNotEmpty ? resp.body : 'Failed to load rooms');
        setState(() {
          timeSlots = [];
          roomsByCategory = {'Study': [], 'Multimedia': [], 'Meeting': []};
        });
        return;
      }

      final data = jsonDecode(resp.body);
      if (data is! Map || data['ok'] != true || data['rooms'] is! List) {
        _snack('Invalid availability response');
        setState(() {
          timeSlots = [];
          roomsByCategory = {'Study': [], 'Multimedia': [], 'Meeting': []};
        });
        return;
      }

      // collect slot labels
      if (data['slots'] is List) {
        final labels = <String>[];
        for (final s in (data['slots'] as List)) {
          final st = (s['start_time'] ?? '').toString();
          final et = (s['end_time'] ?? '').toString();
          if (st.isNotEmpty && et.isNotEmpty) labels.add('$st - $et');
        }
        timeSlots = labels;
      }

      final Map<String, List<Map<String, dynamic>>> grouped = {
        'Study': [],
        'Multimedia': [],
        'Meeting': [],
      };

      for (final r in (data['rooms'] as List)) {
        final name = (r as Map)['name']?.toString() ?? '';
        final desc = (r['description'] ?? '').toString();
        final imageUrl = ApiConfig.resolveUrl(
          (r['image_url'] ?? '').toString(),
        );
        final cap = (r['capacity'] ?? 0) is int
            ? (r['capacity'] as int)
            : int.tryParse('${r['capacity']}') ?? 0;
        Map<String, dynamic> rawStatuses = {};
        if (r['statuses'] is Map<String, dynamic>) {
          rawStatuses = (r['statuses'] as Map<String, dynamic>);
        }

        final Map<String, String> statuses = {
          for (final slot in timeSlots)
            slot: (rawStatuses[slot]?.toString() ?? 'available'),
        };

        final cat = _guessCategory(name);
        grouped[cat]!.add({
          'id': r['id'],
          'name': name,
          'details': desc.isNotEmpty ? desc : 'Room',
          'max': cap, // <- from API
          'statuses': statuses,
          'image': imageUrl.isNotEmpty
              ? imageUrl
              : 'assets/images/study_room_a.jpg',
          'room_status': (r['room_status'] ?? 1),
        });
      }

      // sort: available → fully booked → disabled, then by name
      int priority(Map<String, dynamic> room) {
        final statuses = Map<String, String>.from(room['statuses'] as Map);
        final isFullyBooked = !statuses.values.any((v) => v == 'available');
        final isDisabled = (room['room_status'] ?? 1) == 0;
        if (isDisabled) return 2;
        if (isFullyBooked) return 1;
        return 0;
      }

      for (final cat in grouped.keys) {
        grouped[cat]!.sort((a, b) {
          final pa = priority(a), pb = priority(b);
          if (pa != pb) return pa.compareTo(pb);
          return (a['name'] as String).compareTo(b['name'] as String);
        });
      }

      if (mounted) setState(() => roomsByCategory = grouped);
    } on TimeoutException {
      _snack('Timeout while loading rooms');
    } catch (e) {
      _snack('Network error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ───────────────────────────────────────────────────────────────
  // UI helpers

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  String _formatHeaderDate(DateTime d) {
    const w = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    const m = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    final weekday = w[(d.weekday + 6) % 7];
    final month = m[d.month - 1];
    return '$weekday, $month ${d.day}, ${d.year}';
  }

  Color getStatusColor(String status) {
    switch (status) {
      case 'available':
        return Colors.teal;
      case 'pending':
        return Colors.orange;
      case 'reserved':
        return const Color.fromARGB(255, 12, 143, 209);
      case 'disabled':
        return Colors.red;
      case 'passed':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _guessCategory(String name) {
    final n = name.toLowerCase();
    if (n.contains('multi')) return 'Multimedia';
    if (n.contains('meet')) return 'Meeting';
    return 'Study';
  }

  Future<void> _showSlotsDialog(Map<String, dynamic> room) async {
    final timeSlotsLocal = timeSlots;
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          contentPadding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                room['name'],
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: Color(0xFF003366),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "${room['details']}  •  Max: ${room['max']} people",
                style: const TextStyle(
                  color: Colors.black54,
                  fontSize: 13.5,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              const Divider(height: 1),
            ],
          ),
          content: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: timeSlotsLocal.map((slot) {
              final status = (room['statuses'][slot] as String?) ?? 'unknown';
              final color = getStatusColor(status);
              return IgnorePointer(
                ignoring: true,
                child: RawChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.access_time, size: 16),
                      const SizedBox(width: 6),
                      Text(slot),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          status,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  backgroundColor: Colors.white,
                  shape: const StadiumBorder(
                    side: BorderSide(color: Color(0xFFBDBDBD)),
                  ),
                  onPressed: () {},
                  pressElevation: 0,
                  elevation: 0,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text(
                'Close',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF003366),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final headerHeight = MediaQuery.of(context).size.height * 0.28;
    final rooms = roomsByCategory[selectedCategory] ?? const [];

    return Scaffold(
      backgroundColor: const Color(0xFFD9D9D9),

      // ===== Bottom navigation =====
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
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const StaffDashboard()),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.search, color: Colors.white, size: 28),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text(
                        'You are already on the Browse Room page',
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
                  if (!_loading) _fetchAvailability(); // quick refresh
                },
              ),
              IconButton(
                icon: const Icon(Icons.calendar_today, color: Colors.white),
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

      // ===== Body =====
      body: Column(
        children: [
          // ===== Header =====
          Container(
            width: double.infinity,
            height: headerHeight,
            decoration: const BoxDecoration(
              color: Color(0xFF003366),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(30),
                bottomRight: Radius.circular(30),
              ),
              border: Border(bottom: BorderSide(color: Colors.black, width: 2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 60),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 25),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _HeaderText(
                        title: 'Hi, $_staffFirstName',
                        subtitle: 'Browse Rooms',
                      ),
                      const _LogoutBtn(),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      // Date pill
                      Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 18,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 8,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 30,
                              height: 30,
                              decoration: const BoxDecoration(
                                color: Colors.black87,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.calendar_month,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _formatHeaderDate(DateTime.now()),
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 7),
                      // Manage button
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const StaffRoomManagementPage(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.settings, size: 18),
                        label: const Text('Manage'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF003366),
                          elevation: 0,
                          side: const BorderSide(color: Color(0xFFBDBDBD)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Category chips
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: List.generate(categories.length, (i) {
                final cat = categories[i];
                final isSelected = cat == selectedCategory;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: i == 0 ? 0 : 8,
                      right: i == categories.length - 1 ? 0 : 8,
                    ),
                    child: ChoiceChip(
                      showCheckmark: false,
                      label: Center(child: Text(cat.toLowerCase())),
                      selected: isSelected,
                      backgroundColor: Colors.white,
                      selectedColor: const Color(0xFF184D83),
                      shape: const StadiumBorder(
                        side: BorderSide(color: Color(0xFFBDBDBD), width: 1),
                      ),
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : Colors.black87,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      onSelected: (_) async {
                        setState(() => selectedCategory = cat);
                        if (!_loading) await _fetchAvailability();
                      },
                    ),
                  ),
                );
              }),
            ),
          ),

          // Room cards (read-only, overlay for fully booked / disabled)
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: rooms.length,
                    itemBuilder: (context, index) {
                      const double cardH = 420;
                      const double cardW = 320;
                      final double imgH = cardH * 0.70;
                      final room = rooms[index];

                      final Map<String, String> statuses =
                          Map<String, String>.from(room['statuses'] as Map);
                      final bool isFullyBookedToday = !statuses.values.any(
                        (v) => v == 'available',
                      );
                      final bool isDisabled = (room['room_status'] ?? 1) == 0;

                      final String img = (room['image'] ?? '').toString();
                      final bool isNetwork =
                          img.startsWith('http://') ||
                          img.startsWith('https://');

                      return Container(
                        margin: EdgeInsets.only(
                          left: index == 0 ? 0 : 12,
                          right: index == rooms.length - 1 ? 0 : 12,
                        ),
                        width: cardW,
                        height: cardH,
                        clipBehavior: Clip.hardEdge,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // card
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black12,
                                    blurRadius: 6,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ClipRRect(
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(16),
                                    ),
                                    child: SizedBox(
                                      height: imgH,
                                      width: double.infinity,
                                      child: isNetwork
                                          ? Image.network(
                                              img,
                                              fit: BoxFit.cover,
                                            )
                                          : Image.asset(img, fit: BoxFit.cover),
                                    ),
                                  ),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        10,
                                        16,
                                        10,
                                        8,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            room['name'],
                                            style: const TextStyle(
                                              fontSize: 16.5,
                                              fontWeight: FontWeight.w700,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            "${room['details']}  •  Max : ${room['max']} people",
                                            style: const TextStyle(
                                              color: Colors.black54,
                                              fontSize: 12.5,
                                              height: 1.25,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 15),
                                          Row(
                                            children: [
                                              Container(
                                                width: 28,
                                                height: 28,
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                    0xFFF2F2F2,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(14),
                                                ),
                                                child: const Icon(
                                                  Icons.groups_outlined,
                                                  size: 18,
                                                  color: Colors.black87,
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              ElevatedButton.icon(
                                                onPressed: () =>
                                                    _showSlotsDialog(room),
                                                icon: const Icon(
                                                  Icons.info_outline,
                                                  size: 18,
                                                ),
                                                label: const Text('Details'),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.white,
                                                  foregroundColor: const Color(
                                                    0xFF003366,
                                                  ),
                                                  elevation: 0,
                                                  side: const BorderSide(
                                                    color: Color(0xFFBDBDBD),
                                                  ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 10,
                                                      ),
                                                ),
                                              ),
                                              const Spacer(),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // overlays
                            if (isDisabled || isFullyBookedToday) ...[
                              Positioned.fill(
                                child: Container(
                                  color: Colors.white.withValues(alpha: 0.60),
                                ),
                              ),
                              Positioned(
                                top: 10,
                                left: 0,
                                right: 0,
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.80,
                                      ),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      isDisabled
                                          ? 'This room is disabled'
                                          : 'This room is fully booked for today',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ----- Shared header pieces (keeps your staff style) -----

class _HeaderText extends StatelessWidget {
  const _HeaderText({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final parts = title.split(', ');
    final hiPart = parts.isNotEmpty ? parts.first : 'Hi';
    final namePart = parts.length > 1 ? parts[1] : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$hiPart, ',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold, // bold "Hi,"
                ),
              ),
              TextSpan(
                text: namePart,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.normal, // normal name
                ),
              ),
            ],
          ),
        ),
        Text(
          subtitle,
          style: const TextStyle(color: Colors.white, fontSize: 22),
        ),
      ],
    );
  }
}

class _LogoutBtn extends StatelessWidget {
  const _LogoutBtn();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => showLogoutDialog(context),
      icon: const Icon(Icons.logout_rounded, color: Colors.white, size: 40),
    );
  }
}
