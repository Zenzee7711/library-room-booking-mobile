import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:room_booking_app/logout_function.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

// Image/file pickers
import 'package:image_picker/image_picker.dart'; // Android
import 'package:file_picker/file_picker.dart'; // iOS / Web / Desktop

import 'staff_dashboard.dart';
import 'staff_history.dart';
import 'package:room_booking_app/config/api_config.dart';

class StaffAddRoomPage extends StatefulWidget {
  const StaffAddRoomPage({super.key});

  static const kNavy = Color(0xFF003366);
  static const kGreen = Color(0xFF1FA22A);
  static const kRed = Color(0xFFDA351C);

  @override
  State<StaffAddRoomPage> createState() => _StaffAddRoomPageState();
}

class _StaffAddRoomPageState extends State<StaffAddRoomPage> {

  final _secure = const FlutterSecureStorage();
  String? _jwt;

  // Header name
  String _staffFirst = 'Staff';

  // Form
  final _nameCtl = TextEditingController();
  final _capCtl = TextEditingController();
  final _descCtl = TextEditingController();

  // Image to upload (chosen but not uploaded yet)
  String? _pickedPath;
  String? _pickedName; // for web bytes
  List<int>? _pickedBytes;

  bool _saving = false;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _capCtl.dispose();
    _descCtl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    _jwt = await _secure.read(key: 'jwt');
    await _fetchMe();
  }

  Future<void> _fetchMe() async {
    try {
      final resp = await http
          .get(Uri.parse('${ApiConfig.baseUrl}/common/user_auth'), headers: _authJson())
          .timeout(const Duration(seconds: 8));

      if (resp.statusCode == 200) {
        final d = jsonDecode(resp.body);
        if (d is Map && d['ok'] == true && d['user'] is Map) {
          final u = d['user'] as Map;
          final fn = (u['first_name'] ?? '').toString().trim();
          if (fn.isNotEmpty && mounted) setState(() => _staffFirst = fn);
        }
      }
    } catch (_) {
      /* ignore */
    }
  }

  Map<String, String> _authJson() {
    final h = <String, String>{'Content-Type': 'application/json'};
    final t = _jwt;
    if (t != null && t.isNotEmpty) h['Authorization'] = 'Bearer $t';
    return h;
  }

  Map<String, String> _authMultipart() {
    final h = <String, String>{};
    final t = _jwt;
    if (t != null && t.isNotEmpty) h['Authorization'] = 'Bearer $t';
    return h;
  }

  String _digits(String s) =>
      RegExp(r'\d+').allMatches(s).map((m) => m.group(0)).join();

  Future<void> _pickImage() async {
    if (_picking) return;
    setState(() => _picking = true);

    try {
      if (kIsWeb) {
        final res = await FilePicker.platform.pickFiles(
          allowMultiple: false,
          type: FileType.image,
          withData: true,
        );
        if (res == null || res.files.isEmpty) return;
        final f = res.files.single;
        if (f.bytes == null) return;
        setState(() {
          _pickedBytes = f.bytes!;
          _pickedName = f.name;
          _pickedPath = null; // bytes mode
        });
        _toast('Image selected');
        return;
      }

      if (Platform.isIOS ||
          Platform.isMacOS ||
          Platform.isWindows ||
          Platform.isLinux) {
        final res = await FilePicker.platform.pickFiles(
          allowMultiple: false,
          type: FileType.image,
        );
        if (res == null || res.files.isEmpty) return;
        final f = res.files.single;
        if (f.path != null) {
          setState(() {
            _pickedPath = f.path!;
            _pickedBytes = null;
            _pickedName = f.name;
          });
        } else if (f.bytes != null) {
          setState(() {
            _pickedBytes = f.bytes!;
            _pickedName = f.name;
            _pickedPath = null;
          });
        }
        _toast('Image selected');
        return;
      }

      if (Platform.isAndroid) {
        final picker = ImagePicker();
        final XFile? picked = await picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 92,
        );
        if (picked == null) return;
        setState(() {
          _pickedPath = picked.path;
          _pickedBytes = null;
          _pickedName = null;
        });
        _toast('Image selected');
        return;
      }
    } catch (e) {
      _toast('Picker error: $e');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save() async {
    final name = _nameCtl.text.trim();
    final capStr = _digits(_capCtl.text);
    final cap = capStr.isEmpty ? 0 : int.tryParse(capStr) ?? 0;
    final desc = _descCtl.text.trim();

    if (name.isEmpty) {
      _toast('Room name is required');
      return;
    }
    if (cap < 0) {
      _toast('Capacity must be non-negative');
      return;
    }

    setState(() => _saving = true);
    int? newRoomId;

    try {
      // 1) Create the room
      final resp = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/staff/rooms/create'),
            headers: _authJson(),
            body: jsonEncode({
              'name': name,
              'capacity': cap,
              'description': desc,
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (resp.statusCode != 201 && resp.statusCode != 200) {
        String msg = 'Create failed';
        try {
          final d = jsonDecode(resp.body);
          if (d is Map && d['error'] != null) msg = d['error'].toString();
        } catch (_) {}
        _toast(msg);
        return;
      }

      final data = jsonDecode(resp.body);
      if (data is Map && data['ok'] == true) {
        newRoomId = (data['id'] ?? data['room_id']) is int
            ? data['id'] ?? data['room_id']
            : int.tryParse('${data['id'] ?? data['room_id'] ?? ''}');
      }

      if (newRoomId == null) {
        _toast('Create succeeded but no id returned');
        return;
      }

      // 2) If user picked an image, upload it now
      if (_pickedPath != null || _pickedBytes != null) {
        final req = http.MultipartRequest(
          'POST',
          Uri.parse('${ApiConfig.baseUrl}/rooms/$newRoomId/image'),
        );
        req.headers.addAll(_authMultipart());

        if (_pickedPath != null) {
          req.files.add(
            await http.MultipartFile.fromPath('image', _pickedPath!),
          );
        } else {
          req.files.add(
            http.MultipartFile.fromBytes(
              'image',
              _pickedBytes!,
              filename: _pickedName ?? 'room.jpg',
            ),
          );
        }

        final streamed = await req.send().timeout(const Duration(seconds: 20));
        final uresp = await http.Response.fromStream(streamed);
        if (uresp.statusCode != 200) {
          _toast('Room created, but image upload failed (${uresp.statusCode})');
          // still continue to success dialog
        }
      }

      await _showSuccessThenBack(context);
    } on TimeoutException {
      _toast('Timeout while creating room');
    } catch (e) {
      _toast('Network error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ==== UI ====

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final headerHeight = media.size.height * 0.20;

    return Scaffold(
      // bottom nav (even spacing, home centered)
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          height: 56,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                icon: const Icon(Icons.calendar_today, color: Colors.white),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const StaffHistory()),
                ),
              ),
            ],
          ),
        ),
      ),

      body: Column(
        children: [
          // ===== HEADER (same style, but first name dynamic & no "Aj.") =====
          Container(
            decoration: const BoxDecoration(
              color: StaffAddRoomPage.kNavy,
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
                      // "Hi, {First}" + "Add new room"
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            TextSpan(
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
                                  text: ', $_staffFirst',
                                  style: const TextStyle(
                                    fontSize: 28,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Text(
                            'Add new room',
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
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ===== White form card (UI preserved) =====
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // --- Upload box (no duplicate text) ---
                      InkWell(
                        onTap: _picking ? null : _pickImage,
                        child: Container(
                          height: 150,
                          decoration: BoxDecoration(
                            color: const Color(0xFFD9D9D9),
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 6,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Builder(
                            builder: (_) {
                              final hasImage =
                                  _pickedPath != null || _pickedBytes != null;

                              if (!hasImage) {
                                // Only the centered placeholder BEFORE selecting
                                return Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.image_outlined,
                                        size: 40,
                                        color: Colors.black54,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        _picking
                                            ? 'Opening picker...'
                                            : 'Upload image',
                                        style: const TextStyle(
                                          color: Color(0xFF4A90E2),
                                          decoration: TextDecoration.underline,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }

                              // AFTER selecting: show the preview + bottom "Change image"
                              return Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (_pickedPath != null)
                                    Image.file(
                                      File(_pickedPath!),
                                      fit: BoxFit.cover,
                                    )
                                  else
                                    Image.memory(
                                      Uint8List.fromList(_pickedBytes!),
                                      fit: BoxFit.cover,
                                    ),
                                  Align(
                                    alignment: Alignment.bottomCenter,
                                    child: Container(
                                      color: Colors.white70,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 6,
                                        horizontal: 12,
                                      ),
                                      child: const Text(
                                        'Change image',
                                        style: TextStyle(
                                          color: Color(0xFF4A90E2),
                                          decoration: TextDecoration.underline,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Room name
                      _label('Room name'),
                      _greyField(controller: _nameCtl),
                      const SizedBox(height: 12),

                      // Capacity
                      _label('Capacity'),
                      _greyField(
                        controller: _capCtl,
                        keyboardType: TextInputType.number,
                        hintText: 'e.g., 8',
                      ),
                      const SizedBox(height: 12),

                      // Description
                      _label('Description'),
                      _greyField(
                        controller: _descCtl,
                        minLines: 3,
                        maxLines: 5,
                        height: 72,
                      ),
                      const SizedBox(height: 20),

                      // Save / Cancel buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: StaffAddRoomPage.kGreen,
                              shape: const StadiumBorder(),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 28,
                                vertical: 12,
                              ),
                            ),
                            onPressed: _saving ? null : _save,
                            child: Text(
                              _saving ? 'Saving...' : 'Save',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: StaffAddRoomPage.kRed,
                              shape: const StadiumBorder(),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 22,
                                vertical: 12,
                              ),
                            ),
                            onPressed: () => Navigator.pop(context),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showSuccessThenBack(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: const Padding(
          padding: EdgeInsets.fromLTRB(20, 24, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, size: 120, color: Color(0xFF1FA22A)),
              SizedBox(height: 12),
              Text(
                'Room added successfully',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // close dialog
    Navigator.of(context).pop(); // back to Room Management
  }

  // ===== Shared style helpers =====
  static Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
    ),
  );

  static Widget _greyField({
    required TextEditingController controller,
    double height = 44,
    int minLines = 1,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? hintText,
  }) {
    return Container(
      height: maxLines > 1 ? null : height,
      decoration: BoxDecoration(
        color: const Color(0xFFD9D9D9),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      child: TextField(
        controller: controller,
        minLines: minLines,
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          hintText: hintText,
          border: InputBorder.none,
        ),
      ),
    );
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }
}
