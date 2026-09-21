import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:room_booking_app/logout_function.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

// Pickers
import 'package:image_picker/image_picker.dart'; // Android branch
import 'package:file_picker/file_picker.dart';   // iOS/Web/Desktop branch

import 'staff_dashboard.dart';
import 'staff_history.dart';
import 'package:room_booking_app/config/api_config.dart';

class StaffEditRoomPage extends StatefulWidget {
  const StaffEditRoomPage({
    super.key,
    required this.roomId,
    this.initialName = 'Meeting Room A',
    this.initialCapacity = '4 People', // can be "4" or "4 People"
    this.initialDescription = 'Quiet Room, Aircon, Projector',
    required this.imagePath, // may be http(s) URL (backend) or asset path
  });

  final int roomId;
  final String initialName;
  final String initialCapacity;
  final String initialDescription;
  final String imagePath;

  static const kNavy  = Color(0xFF003366);
  static const kGreen = Color(0xFF1FA22A);
  static const kRed   = Color(0xFFDA351C);

  @override
  State<StaffEditRoomPage> createState() => _StaffEditRoomPageState();
}

class _StaffEditRoomPageState extends State<StaffEditRoomPage> {
  final _secure = const FlutterSecureStorage();

  late final TextEditingController _nameCtl;
  late final TextEditingController _capCtl;
  late final TextEditingController _descCtl;

  String _staffName = 'Staff';
  String? _jwt;
  bool _saving = false;
  bool _uploading = false;

  // current preview image (network URL or asset path)
  late String _currentImagePath;
  bool get _isNetwork =>
      _currentImagePath.startsWith('http://') || _currentImagePath.startsWith('https://');

  @override
  void initState() {
    super.initState();
    _nameCtl = TextEditingController(text: widget.initialName);
    _capCtl  = TextEditingController(
      text: _extractDigits(widget.initialCapacity),
    );
    _descCtl = TextEditingController(text: widget.initialDescription);
    _currentImagePath = widget.imagePath;
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
    // fetch staff first name
    try {
      final resp = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/common/user_auth'),
        headers: _authJson(),
      ).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data is Map && data['ok'] == true && data['user'] is Map) {
          final u = data['user'] as Map;
          final fn = (u['first_name'] ?? '').toString().trim();
          if (fn.isNotEmpty && mounted) setState(() => _staffName = fn);
        }
      }
    } catch (_) {/* ignore */}
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

  String _extractDigits(String s) {
    final digits = RegExp(r'\d+').allMatches(s).map((m) => m.group(0)).join();
    return digits;
  }

  Future<void> _save() async {
    final name = _nameCtl.text.trim();
    final capStr = _extractDigits(_capCtl.text);
    final cap = capStr.isEmpty ? 0 : int.tryParse(capStr) ?? 0;
    final desc = _descCtl.text.trim();

    if (name.isEmpty) {
      _toast('Room name is required');
      return;
    }
    if (cap < 0) {
      _toast('Capacity must be a non-negative number');
      return;
    }

    setState(() => _saving = true);
    try {
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/staff/rooms/${widget.roomId}/edit'),
        headers: _authJson(),
        body: jsonEncode({
          'name': name,
          'description': desc,
          'capacity': cap, // <- backend expects this now
        }),
      ).timeout(const Duration(seconds: 12));

      if (resp.statusCode == 200) {
        await _showSuccessThenBack(context);
      } else {
        String msg = 'Save failed';
        try {
          final d = jsonDecode(resp.body);
          if (d is Map && d['error'] != null) msg = d['error'].toString();
        } catch (_) {}
        _toast(msg);
      }
    } on TimeoutException {
      _toast('Timeout while saving');
    } catch (e) {
      _toast('Network error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ========= Image picking & upload =========

  Future<void> _pickAndUploadImage() async {
    if (_uploading) return;
    setState(() => _uploading = true);

    try {
      if (kIsWeb) {
        // Web → file_picker with bytes
        final res = await FilePicker.platform.pickFiles(
          allowMultiple: false, type: FileType.image, withData: true);
        if (res == null || res.files.isEmpty || res.files.single.bytes == null) return;
        await _uploadBytesAndSet(res.files.single.name, res.files.single.bytes!);
        return;
      }

      if (Platform.isIOS || Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        // iOS/Desktop → file_picker (more reliable than image_picker channel on iOS)
        final res = await FilePicker.platform.pickFiles(
          allowMultiple: false, type: FileType.image);
        if (res == null || res.files.isEmpty) return;

        final file = res.files.single;
        if (file.path != null) {
          await _uploadFilePathAndSet(file.path!);
        } else if (file.bytes != null) {
          await _uploadBytesAndSet(file.name, file.bytes!);
        } else {
          _toast('Could not read selected file');
        }
        return;
      }

      if (Platform.isAndroid) {
        // Android → image_picker
        final picker = ImagePicker();
        final XFile? picked = await picker.pickImage(
          source: ImageSource.gallery, imageQuality: 92);
        if (picked == null) return;
        await _uploadFilePathAndSet(picked.path);
        return;
      }
    } catch (e) {
      _toast('Picker error: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _uploadFilePathAndSet(String path) async {
    final req = http.MultipartRequest(
      'POST', Uri.parse('${ApiConfig.baseUrl}/rooms/${widget.roomId}/image'));
    req.headers.addAll(_authMultipart());
    req.files.add(await http.MultipartFile.fromPath('image', path));

    final streamed = await req.send().timeout(const Duration(seconds: 20));
    final resp = await http.Response.fromStream(streamed);

    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      if (data is Map && data['ok'] == true && data['url'] is String) {
        setState(() => _currentImagePath = ApiConfig.resolveUrl(data['url'] as String));
        _toast('Image updated');
      } else {
        _toast('Upload succeeded but response invalid');
      }
    } else {
      _toast('Upload failed (${resp.statusCode})');
    }
  }

  Future<void> _uploadBytesAndSet(String filename, List<int> bytes) async {
    final req = http.MultipartRequest(
      'POST', Uri.parse('${ApiConfig.baseUrl}/rooms/${widget.roomId}/image'));
    req.headers.addAll(_authMultipart());
    req.files.add(http.MultipartFile.fromBytes('image', bytes, filename: filename));

    final streamed = await req.send().timeout(const Duration(seconds: 20));
    final resp = await http.Response.fromStream(streamed);

    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      if (data is Map && data['ok'] == true && data['url'] is String) {
        setState(() => _currentImagePath = ApiConfig.resolveUrl(data['url'] as String));
        _toast('Image updated');
      } else {
        _toast('Upload succeeded but response invalid');
      }
    } else {
      _toast('Upload failed (${resp.statusCode})');
    }
  }

  // ========= UI =========

  @override
  Widget build(BuildContext context) {
    final headerHeight = MediaQuery.of(context).size.height * 0.20;

    return Scaffold(
      // Bottom navigation
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          height: 56,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 1),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3))],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                onPressed: () => Navigator.maybePop(context),
              ),
              IconButton(
                icon: const Icon(Icons.home_filled, color: Colors.white, size: 28),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StaffDashboard())),
              ),
              IconButton(
                icon: const Icon(Icons.calendar_today, color: Colors.white),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StaffHistory())),
              ),
            ],
          ),
        ),
      ),

      body: Column(
        children: [
          // header (same style; first name dynamic)
          Container(
            decoration: const BoxDecoration(
              color: StaffEditRoomPage.kNavy,
              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
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
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(TextSpan(children: [
                            const TextSpan(
                              text: 'Hi, ',
                              style: TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                            TextSpan(
                              text: _staffName, // Aj.Firstname
                              style: const TextStyle(fontSize: 28, color: Colors.white),
                            ),
                          ])),
                          const Text('Edit the Room', style: TextStyle(fontSize: 25, color: Colors.white)),
                        ],
                      ),
                      IconButton(
                        onPressed: () => showLogoutDialog(context),
                        icon: const Icon(Icons.logout_rounded, color: Colors.white, size: 40),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // form card
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Image preview + Change image
                      Container(
                        height: 150,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD9D9D9),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _isNetwork
                                ? Image.network(_currentImagePath, fit: BoxFit.cover)
                                : Image.asset(_currentImagePath, fit: BoxFit.cover),
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: InkWell(
                                onTap: _uploading ? null : _pickAndUploadImage,
                                child: Container(
                                  color: Colors.white70,
                                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                                  child: Text(
                                    _uploading ? 'Uploading...' : 'Change image',
                                    style: const TextStyle(
                                      color: Color(0xFF4A90E2),
                                      decoration: TextDecoration.underline,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      _label('Room name'),
                      _greyField(controller: _nameCtl),

                      const SizedBox(height: 12),
                      _label('Capacity'),
                      _greyField(
                        controller: _capCtl,
                        keyboardType: TextInputType.number,
                        hint: 'e.g., 8',
                      ),

                      const SizedBox(height: 12),
                      _label('Description'),
                      _greyField(
                        controller: _descCtl,
                        minLines: 3,
                        maxLines: 5,
                      ),

                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: StaffEditRoomPage.kGreen,
                              shape: const StadiumBorder(),
                              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                            ),
                            onPressed: _saving ? null : _save,
                            child: Text(
                              _saving ? 'Saving...' : 'Save',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                            ),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: StaffEditRoomPage.kRed,
                              shape: const StadiumBorder(),
                              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                            ),
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
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

  static Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Align(alignment: Alignment.centerLeft, child: Text(t, style: const TextStyle(fontWeight: FontWeight.w600))),
      );

  // TextField styled like your grey boxes
  static Widget _greyField({
    required TextEditingController controller,
    TextInputType? keyboardType,
    int minLines = 1,
    int maxLines = 1,
    String? hint,
  }) {
    return Container(
      decoration: BoxDecoration(color: const Color(0xFFD9D9D9), borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        minLines: minLines,
        maxLines: maxLines,
        decoration: InputDecoration(
          hintText: hint,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        ),
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
              Text('Room edited successfully', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
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

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }
}