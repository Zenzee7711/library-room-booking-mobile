import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:room_booking_app/logout_function.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:room_booking_app/staff_browsing.dart';
import 'staff_add_room.dart';
import 'staff_edit_room.dart';
import 'package:room_booking_app/config/api_config.dart';
import 'staff_dashboard.dart'; // class: StaffDashboard
import 'staff_history.dart'; // class: StaffHistory

class StaffRoomManagementPage extends StatefulWidget {
  const StaffRoomManagementPage({super.key});
  @override
  State<StaffRoomManagementPage> createState() =>
      _StaffRoomManagementPageState();
}

class _StaffRoomManagementPageState extends State<StaffRoomManagementPage> {
  static const kNavy = Color(0xFF003366);

  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  String _staffName = 'Staff';
  String? _jwt;
  bool _loading = false;

  // Rooms loaded from API
  final List<_RoomData> _rooms = [];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    _jwt = await _secure.read(key: 'jwt');
    await _fetchMe();
    await _fetchRooms();
  }

  Map<String, String> _authJsonHeaders() {
    final h = <String, String>{'Content-Type': 'application/json'};
    final t = _jwt;
    if (t != null && t.isNotEmpty) h['Authorization'] = 'Bearer $t';
    return h;
  }

  Future<void> _fetchMe() async {
    try {
      final resp = await http
          .get(
            Uri.parse('${ApiConfig.baseUrl}/common/user_auth'),
            headers: _authJsonHeaders(),
          )
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data is Map && data['ok'] == true && data['user'] is Map) {
          final u = data['user'] as Map;
          final fn = (u['first_name'] ?? '').toString().trim();
          if (fn.isNotEmpty && mounted) setState(() => _staffName = fn);
        }
      }
    } catch (_) {
      /* ignore */
    }
  }

  Future<void> _fetchRooms() async {
    setState(() => _loading = true);
    try {
      // expects: [{ id, name, description, image_url, room_status(0/1), active_bookings(optional) }]
      final resp = await http
          .get(
            Uri.parse('${ApiConfig.baseUrl}/staff/rooms/management'),
            headers: _authJsonHeaders(),
          )
          .timeout(const Duration(seconds: 12));

      if (resp.statusCode != 200) {
        _snack(resp.body.isNotEmpty ? resp.body : 'Failed to load rooms');
        if (mounted) setState(() => _rooms.clear());
        return;
      }

      final data = jsonDecode(resp.body);
      if (data is! Map || data['ok'] != true || data['rooms'] is! List) {
        _snack('Invalid rooms response');
        if (mounted) setState(() => _rooms.clear());
        return;
      }

      final List rows = data['rooms'];
      final out = <_RoomData>[];

      for (final r in rows) {
        final id = r['id'];
        final name = (r['name'] ?? '').toString();
        final desc = (r['description'] ?? '').toString();
        final image = ApiConfig.resolveUrl((r['image_url'] ?? '').toString());
        final status = (r['room_status'] == 1)
            ? RoomStatus.available
            : RoomStatus.disabled;

        // use capacity from API directly
        final int cap = (r['capacity'] is int)
            ? (r['capacity'] as int)
            : int.tryParse('${r['capacity'] ?? 0}') ?? 0;

        out.add(
          _RoomData(
            id: id is int ? id : int.tryParse('$id') ?? 0,
            name: name,
            capacity: cap,
            status: status,
            imageUrl: image,
            description: desc,
          ),
        );
      }

      if (mounted) {
        setState(() {
          _rooms
            ..clear()
            ..addAll(out);
        });
      }
    } on TimeoutException {
      _snack('Timeout while loading rooms');
    } catch (e) {
      _snack('Network error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleStatus(_RoomData room) async {
    // optimistic lock in UI after success only
    try {
      final resp = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/staff/rooms/${room.id}/toggle'),
            headers: _authJsonHeaders(),
            body: jsonEncode({}),
          )
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        // flip local status
        final i = _rooms.indexWhere((e) => e.id == room.id);
        if (i != -1 && mounted) {
          setState(() {
            _rooms[i] = _rooms[i].copyWith(
              status: room.status == RoomStatus.available
                  ? RoomStatus.disabled
                  : RoomStatus.available,
            );
          });
        }
        _snack(
          room.status == RoomStatus.available
              ? 'Room disabled'
              : 'Room enabled',
        );
      } else {
        // 409 is expected when there are active bookings (Waiting/Approved)
        String msg = 'Toggle failed';
        try {
          final d = jsonDecode(resp.body);
          if (d is Map && d['error'] != null) msg = d['error'].toString();
        } catch (_) {}
        _snack(msg);
      }
    } on TimeoutException {
      _snack('Timeout while toggling room');
    } catch (e) {
      _snack('Network error: $e');
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // Map room name -> local fallback asset (only used if no server image)
  String _fallbackAssetFor(String name) {
    final n = name.toLowerCase();
    if (n.startsWith('study room a')) return 'assets/images/study_room_a.jpg';
    if (n.startsWith('multimedia room a')) {
      return 'assets/images/multimedia_room_a.jpg';
    }
    return 'assets/images/study_room_b.jpg';
  }

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    final headerHeight = MediaQuery.of(context).size.height * 0.26;

    return Scaffold(
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
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const StaffBrowsing()),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.calendar_today, color: Colors.white),
                onPressed: () {
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

      // ===== PAGE BODY =====
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ===== Header =====
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
                      // "Hi, Staff" -> bold only "Hi," and keep name normal; name from /common/user_auth
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
                                  text: _staffName,
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
                            'Room Management',
                            style: TextStyle(fontSize: 25, color: Colors.white),
                          ),
                        ],
                      ),
                      // Logout
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

                // ===== existing "Add New Room" chip (navigate, then refresh on return) =====
                const SizedBox(height: 35),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: GestureDetector(
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const StaffAddRoomPage(),
                        ),
                      );
                      // refresh list after adding
                      await _fetchRooms();
                    },
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(
                        color: const Color(0xFFC9C0C0),
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 6,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(width: 14),
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: Colors.grey,
                            child: Icon(
                              Icons.add,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Add New Room',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          SizedBox(width: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ===== ROOM LIST =====
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (_rooms.isEmpty
                      ? const _EmptyRooms()
                      : RefreshIndicator(
                          onRefresh: _fetchRooms,
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                            itemCount: _rooms.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, i) {
                              final r = _rooms[i];
                              return _RoomCard(
                                data: r,
                                imageFallback: _fallbackAssetFor(r.name),
                                onToggle: () => _toggleStatus(r),
                                onEdit: () async {
                                  // If the API gave us a URL, pass it through. Otherwise pass a local fallback asset.
                                  final imageForEdit = (r.imageUrl.isNotEmpty)
                                      ? r.imageUrl
                                      : _fallbackAssetFor(r.name);

                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => StaffEditRoomPage(
                                        roomId: r.id,
                                        initialName: r.name,
                                        initialCapacity: r.capacity > 0
                                            ? '${r.capacity} People'
                                            : '',
                                        initialDescription: r.description,
                                        imagePath:
                                            imageForEdit, // <-- use URL if we have one
                                      ),
                                    ),
                                  );
                                  await _fetchRooms(); // refresh after returning
                                },
                              );
                            },
                          ),
                        )),
          ),
        ],
      ),
    );
  }
}

enum RoomStatus { available, disabled }

class _RoomData {
  final int id;
  final String name;
  final int capacity; // optional, derived from description if present
  final RoomStatus status;
  final String imageUrl; // may be empty → use fallback asset in card
  final String description; // for edit page

  const _RoomData({
    required this.id,
    required this.name,
    required this.capacity,
    required this.status,
    required this.imageUrl,
    required this.description,
  });

  _RoomData copyWith({
    int? id,
    String? name,
    int? capacity,
    RoomStatus? status,
    String? imageUrl,
    String? description,
  }) {
    return _RoomData(
      id: id ?? this.id,
      name: name ?? this.name,
      capacity: capacity ?? this.capacity,
      status: status ?? this.status,
      imageUrl: imageUrl ?? this.imageUrl,
      description: description ?? this.description,
    );
  }
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.data,
    required this.onToggle,
    required this.onEdit,
    required this.imageFallback,
  });

  final _RoomData data;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final String imageFallback;

  static const kGreen = Color(0xFF1FA22A);
  static const kRed = Color(0xFFDA351C);

  @override
  Widget build(BuildContext context) {
    final isAvailable = data.status == RoomStatus.available;

    final bool isNetwork =
        data.imageUrl.startsWith('http://') ||
        data.imageUrl.startsWith('https://');
    final imgWidget = isNetwork && data.imageUrl.isNotEmpty
        ? Image.network(data.imageUrl, width: 92, height: 72, fit: BoxFit.cover)
        : Image.asset(imageFallback, width: 92, height: 72, fit: BoxFit.cover);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: imgWidget,
            ),
            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Capacity : ${data.capacity > 0 ? data.capacity : '-'} people',
                    style: const TextStyle(color: Colors.black87, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Text(
                        'Status : ',
                        style: TextStyle(color: Colors.black87, fontSize: 15),
                      ),
                      Text(
                        isAvailable ? 'Available' : 'Disabled',
                        style: TextStyle(
                          color: isAvailable ? kGreen : kRed,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _roundIcon(
                  icon: Icons.edit_outlined,
                  bg: const Color(0xFFF0F0F0),
                  fg: Colors.black87,
                  onTap: onEdit,
                ),
                const SizedBox(height: 10),
                _roundIcon(
                  icon: Icons.power_settings_new,
                  bg: isAvailable ? kRed : kGreen,
                  fg: Colors.white,
                  onTap: onToggle,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _roundIcon({
    required IconData icon,
    required Color bg,
    required Color fg,
    required VoidCallback onTap,
  }) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: Icon(icon, color: fg, size: 20),
        onPressed: onTap,
      ),
    );
  }
}

class _EmptyRooms extends StatelessWidget {
  const _EmptyRooms();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      children: const [
        SizedBox(height: 80),
        Icon(Icons.meeting_room_outlined, size: 72, color: Colors.black26),
        SizedBox(height: 12),
        Center(
          child: Text(
            'No rooms yet',
            style: TextStyle(fontSize: 18, color: Colors.black54),
          ),
        ),
        SizedBox(height: 8),
        Center(
          child: Text(
            'Tap "Add New Room" to create one',
            style: TextStyle(color: Colors.black45),
          ),
        ),
      ],
    );
  }
}
