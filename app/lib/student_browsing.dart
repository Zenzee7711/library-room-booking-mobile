import 'dart:ui';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:room_booking_app/logout_function.dart';
import 'package:room_booking_app/student_history.dart';
import 'package:room_booking_app/config/api_config.dart';

class StudentBrowsing extends StatefulWidget {
  const StudentBrowsing({super.key});

  @override
  State<StudentBrowsing> createState() => _StudentBrowsingState();
}

class _StudentBrowsingState extends State<StudentBrowsing> {
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  String? _jwt;
  String _firstName = '';
  late final String _todayYMD;

  final List<String> categories = ['Study', 'Multimedia', 'Meeting'];
  String selectedCategory = 'Multimedia';
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
    await _fetchMe();
    await _fetchAvailability();
  }

  Map<String, String> _authHeaders() {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (_jwt != null && _jwt!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_jwt';
    }
    return headers;
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
        return Colors.red; // room offline only
      case 'passed':
        return Colors.grey; // past slots
      default:
        return Colors.grey;
    }
  }

  Color _chipBg(String status) => getStatusColor(status).withOpacity(0.12);

  String _guessCategory(String name) {
    final n = name.toLowerCase();
    if (n.contains('multi')) return 'Multimedia';
    if (n.contains('meet')) return 'Meeting';
    return 'Study';
  }

  Future<void> _fetchMe() async {
    try {
      final resp = await http
          .get(Uri.parse('${ApiConfig.baseUrl}/common/user_auth'), headers: _authHeaders())
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data is Map && data['ok'] == true && data['user'] is Map) {
          final u = data['user'] as Map;
          final fn = (u['first_name'] ?? '').toString().trim();
          if (fn.isNotEmpty && mounted) setState(() => _firstName = fn);
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchAvailability() async {
    setState(() => _loading = true);
    try {
      final url = Uri.parse(
        '${ApiConfig.baseUrl}/common/rooms/availability?date=$_todayYMD',
      );
      final resp = await http
          .get(url, headers: _authHeaders())
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        if (data['ok'] == true && data['rooms'] is List) {
          // collect slot labels
          if (data['slots'] is List) {
            final List list = data['slots'];
            final labels = <String>[];
            for (final s in list) {
              final st = (s['start_time'] ?? '').toString();
              final et = (s['end_time'] ?? '').toString();
              if (st.length >= 2 && et.length >= 2) labels.add('$st - $et');
            }
            if (labels.isNotEmpty) timeSlots = labels;
          }

          final List rooms = data['rooms'];
          final Map<String, List<Map<String, dynamic>>> grouped = {
            'Study': [],
            'Multimedia': [],
            'Meeting': [],
          };

          for (final r in rooms) {
            final name = (r['name'] ?? '').toString();
            final desc = (r['description'] ?? '').toString();
            final imageUrl = ApiConfig.resolveUrl((r['image_url'] ?? '').toString());
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
              'max': cap,
              'statuses': statuses,
              'image': imageUrl.isNotEmpty
                  ? imageUrl
                  : 'assets/images/study_room_a.jpg',
              'room_status': (r['room_status'] ?? 1),
            });
          }

          // ── sort: available first, then fully booked, and disabled last
          int priority(Map<String, dynamic> room) {
            final statuses = Map<String, String>.from(room['statuses'] as Map);
            final isFullyBooked = !statuses.values.any((v) => v == 'available');
            final isDisabled = (room['room_status'] ?? 1) == 0;
            if (isDisabled) return 2; // disabled → last
            if (isFullyBooked) return 1; // fully booked → after available
            return 0; // available → first
          }

          for (final cat in grouped.keys) {
            grouped[cat]!.sort((a, b) {
              final pa = priority(a);
              final pb = priority(b);
              if (pa != pb) return pa.compareTo(pb);
              // tie-breaker by name to keep stable
              return (a['name'] as String).compareTo(b['name'] as String);
            });
          }

          if (mounted) setState(() => roomsByCategory = grouped);
        } else {
          _snack('Invalid availability response');
        }
      } else {
        _snack(
          resp.body.isNotEmpty ? resp.body : 'Failed to load availability',
        );
      }
    } on TimeoutException {
      _snack('Timeout while loading availability');
    } catch (e) {
      _snack('Network error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _createBooking({
    required int roomId,
    required String slotLabel,
    required String objective,
  }) async {
    try {
      final start = slotLabel.split(' - ').first;
      final ts = await http
          .get(Uri.parse('${ApiConfig.baseUrl}/time-slots'), headers: _authHeaders())
          .timeout(const Duration(seconds: 8));
      if (ts.statusCode != 200) {
        _snack('Cannot load time slots');
        return false;
      }
      final tsData = jsonDecode(ts.body);
      if (tsData is! Map || tsData['ok'] != true || tsData['slots'] is! List) {
        _snack('Invalid time slots');
        return false;
      }
      int? slotId;
      for (final s in (tsData['slots'] as List)) {
        final st = (s['start_time'] ?? '').toString().substring(0, 5);
        if (st == start) {
          slotId = s['slot_id'] as int?;
          break;
        }
      }
      if (slotId == null) {
        _snack('Slot not found');
        return false;
      }

      final resp = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/student/bookings'),
            headers: _authHeaders(),
            body: jsonEncode({
              'room_id': roomId,
              'slot_id': slotId,
              'booking_date': _todayYMD,
              'objective': objective,
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (resp.statusCode == 201) {
        return true;
      } else {
        try {
          final err = jsonDecode(resp.body);
          _snack(
            err is Map && err['error'] != null
                ? err['error']
                : 'Booking failed',
          );
        } catch (_) {
          _snack(resp.body.isNotEmpty ? resp.body : 'Booking failed');
        }
        return false;
      }
    } catch (e) {
      _snack('Booking error: $e');
      return false;
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _showSlotsDialog(Map<String, dynamic> room) async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  room['name'],
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
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
              children: timeSlots.map((slot) {
                final status =
                    (room['statuses'][slot] as String?) ?? 'available';
                final enabled = status == 'available';
                final color = getStatusColor(status);

                return InputChip(
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
                          color: color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  labelPadding: const EdgeInsets.symmetric(horizontal: 10),
                  backgroundColor: _chipBg(status),
                  onPressed: enabled
                      ? () async {
                          Navigator.of(ctx).pop();
                          await _showConfirmDialog(room: room, slot: slot);
                        }
                      : null,
                  shape: const StadiumBorder(
                    side: BorderSide(color: Color(0xFFE0E0E0)),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showConfirmDialog({
    required Map<String, dynamic> room,
    required String slot,
  }) async {
    final controller = TextEditingController();
    bool canConfirm = false;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
              child: AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                title: const Text(
                  'Confirm Booking',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 16,
                          ),
                          children: [
                            const TextSpan(text: 'Session in '),
                            TextSpan(
                              text: room['name'],
                              style: const TextStyle(
                                color: Colors.orange,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(Icons.calendar_month, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            _formatHeaderDate(DateTime.now()),
                            style: const TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.access_time, size: 18),
                          const SizedBox(width: 6),
                          Text(slot, style: const TextStyle(fontSize: 14)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Objective (required)',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: controller,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: 'e.g., Group study for CS101 assignment',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onChanged: (v) => setStateDialog(
                          () => canConfirm = v.trim().isNotEmpty,
                        ),
                      ),
                    ],
                  ),
                ),
                actionsAlignment: MainAxisAlignment.spaceEvenly,
                actions: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: canConfirm
                        ? () async {
                            Navigator.of(ctx).pop();
                            final ok = await _createBooking(
                              roomId: (room['id'] as int),
                              slotLabel: slot,
                              objective: controller.text.trim(),
                            );
                            if (ok) {
                              setState(() {
                                final cat = _guessCategory(
                                  (room['name'] as String),
                                );
                                final list = roomsByCategory[cat]!;
                                final idx = list.indexWhere(
                                  (e) => e['id'] == room['id'],
                                );
                                if (idx >= 0) {
                                  final statuses = Map<String, String>.from(
                                    list[idx]['statuses'] as Map,
                                  );
                                  statuses[slot] = 'pending';
                                  list[idx]['statuses'] = statuses;
                                }
                              });
                              await _showSuccessDialog();
                              await _fetchAvailability();
                            }
                          }
                        : null,
                    child: const Text('Confirm'),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showSuccessDialog() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: const Padding(
          padding: EdgeInsets.fromLTRB(20, 24, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, size: 140, color: Colors.green),
              SizedBox(height: 14),
              Text(
                'Your reservation is completed',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
    await Future.delayed(const Duration(milliseconds: 1200));
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
  }

  @override
  Widget build(BuildContext context) {
    final headerHeight = MediaQuery.of(context).size.height * 0.28;
    final rooms = roomsByCategory[selectedCategory] ?? const [];

    return Scaffold(
      backgroundColor: const Color(0xFFD9D9D9),
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
                },
              ),
              IconButton(
                icon: const Icon(Icons.calendar_today, color: Colors.white),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const StudentHistory()),
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          // Header
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
                        title: _firstName.isNotEmpty
                            ? 'Hi, $_firstName'
                            : 'Hi,',
                        subtitle: 'Reserve the room',
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
                const SizedBox(height: 40),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
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
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onSelected: (_) async {
                        if (_loading) return;
                        setState(() => selectedCategory = cat);
                        await _fetchAvailability();
                      },
                    ),
                  ),
                );
              }),
            ),
          ),

          const SizedBox(height: 5),

          // Room cards
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
                            // Card
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
                                  // Image
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
                                  // Info
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

                            // Overlay if fully booked or disabled (dim + banner)
                            if (isDisabled || isFullyBookedToday) ...[
                              Positioned.fill(
                                child: Container(
                                  color: Colors.white.withOpacity(0.60),
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
                                      color: Colors.black.withOpacity(0.80),
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

class _HeaderText extends StatelessWidget {
  const _HeaderText({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.bold,
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
