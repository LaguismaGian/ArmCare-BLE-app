import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../backend/database_service.dart';
import 'hr_recorder_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Profile? _profile;
  Caregiver? _caregiver;
  List<Contact> _contacts = [];
  HrSession? _latestHr;
  int _hrSessionCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    final profile = await DatabaseService.instance.getProfile();
    final caregiver = await DatabaseService.instance.getCaregiver();
    final contacts = await DatabaseService.instance.getAllContacts();
    final latestHr = await DatabaseService.instance.getLatestHrSession();
    final allHr = await DatabaseService.instance.getAllHrSessions();

    if (!mounted) return;
    setState(() {
      _profile = profile;
      _caregiver = caregiver;
      _contacts = contacts;
      _latestHr = latestHr;
      _hrSessionCount = allHr.length;
      _isLoading = false;
    });
  }

  // ===== PROFILE EDIT =====

  Future<void> _editText({
    required String title,
    required String currentValue,
    required void Function(String) onSave,
    int? maxLines,
    TextInputType? keyboardType,
  }) async {
    final controller = TextEditingController(text: currentValue);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: maxLines,
          keyboardType: keyboardType,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null) onSave(result);
  }

  Future<void> _pickPhoto({required bool isProfile}) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 85,
    );
    if (picked == null) return;

    if (isProfile) {
      final p = _profile ??
          Profile(
            name: '',
            gender: '',
            age: 0,
            address: '',
            medicalCondition: '',
          );
      final updated = Profile(
        name: p.name,
        photoPath: picked.path,
        gender: p.gender,
        age: p.age,
        address: p.address,
        emergencyContactId: p.emergencyContactId,
        medicalCondition: p.medicalCondition,
      );
      await DatabaseService.instance.saveProfile(updated);
    } else {
      final c = _caregiver ??
          Caregiver(
            name: '',
            age: 0,
            address: '',
            phone: '',
            relationship: '',
          );
      final updated = Caregiver(
        name: c.name,
        photoPath: picked.path,
        age: c.age,
        address: c.address,
        phone: c.phone,
        relationship: c.relationship,
      );
      await DatabaseService.instance.saveCaregiver(updated);
    }
    _loadAll();
  }

  Future<void> _saveProfile(Profile p) async {
    await DatabaseService.instance.saveProfile(p);
    _loadAll();
  }

  Future<void> _saveCaregiver(Caregiver c) async {
    await DatabaseService.instance.saveCaregiver(c);
    _loadAll();
  }

  Future<void> _pickEmergencyContact() async {
    if (_contacts.isEmpty) {
      _showSnack('No contacts saved. Add one from Emergency Contacts.');
      return;
    }
    final picked = await showDialog<Contact>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Select Emergency Contact'),
        children: _contacts
            .map((c) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, c),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('${c.name} — ${c.phone}'),
                  ),
                ))
            .toList(),
      ),
    );
    if (picked == null) return;
    final p = _profile ??
        Profile(
          name: '',
          gender: '',
          age: 0,
          address: '',
          medicalCondition: '',
        );
    final updated = Profile(
      name: p.name,
      photoPath: p.photoPath,
      gender: p.gender,
      age: p.age,
      address: p.address,
      emergencyContactId: picked.id,
      medicalCondition: p.medicalCondition,
    );
    await _saveProfile(updated);
  }

  String _contactName(int? id) {
    if (id == null) return 'Not set';
    final c = _contacts.firstWhere(
      (x) => x.id == id,
      orElse: () => Contact(name: 'Unknown', phone: ''),
    );
    return c.name;
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ===== HR RECORDER =====

  Future<void> _openHrRecorder() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const HrRecorderScreen()),
    );
    _loadAll(); // refresh latest HR after returning
  }

  // ===== BUILD =====

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Colors.indigo[700],
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildProfileSection(),
            const SizedBox(height: 20),
            _buildCaregiverSection(),
            const SizedBox(height: 20),
            _buildHrSection(),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  // ===== PROFILE SECTION =====

  Widget _buildProfileSection() {
    final p = _profile;
    return _buildCard(
      title: 'User Information',
      titleIcon: Icons.person,
      child: Column(
        children: [
          _buildPhoto(
            photoPath: p?.photoPath,
            onTap: () => _pickPhoto(isProfile: true),
          ),
          const SizedBox(height: 12),
          _buildField(
            label: 'Name',
            value: p?.name ?? 'Not set',
            onTap: () => _editText(
              title: 'Name',
              currentValue: p?.name ?? '',
              onSave: (v) => _saveProfile(Profile(
                name: v,
                photoPath: p?.photoPath,
                gender: p?.gender ?? '',
                age: p?.age ?? 0,
                address: p?.address ?? '',
                emergencyContactId: p?.emergencyContactId,
                medicalCondition: p?.medicalCondition ?? '',
              )),
            ),
          ),
          _buildField(
            label: 'Gender',
            value: (p?.gender.isEmpty ?? true) ? 'Not set' : p!.gender,
            onTap: () async {
              final picked = await showDialog<String>(
                context: context,
                builder: (context) => SimpleDialog(
                  title: const Text('Gender'),
                  children: ['Male', 'Female', 'Other']
                      .map((g) => SimpleDialogOption(
                            onPressed: () => Navigator.pop(context, g),
                            child: Text(g),
                          ))
                      .toList(),
                ),
              );
              if (picked != null && p != null) {
                await _saveProfile(Profile(
                  name: p.name,
                  photoPath: p.photoPath,
                  gender: picked,
                  age: p.age,
                  address: p.address,
                  emergencyContactId: p.emergencyContactId,
                  medicalCondition: p.medicalCondition,
                ));
              }
            },
          ),
          _buildField(
            label: 'Age',
            value: (p?.age ?? 0) == 0 ? 'Not set' : '${p!.age}',
            onTap: () => _editText(
              title: 'Age',
              currentValue: (p?.age ?? 0) == 0 ? '' : '${p!.age}',
              keyboardType: TextInputType.number,
              onSave: (v) => _saveProfile(Profile(
                name: p?.name ?? '',
                photoPath: p?.photoPath,
                gender: p?.gender ?? '',
                age: int.tryParse(v) ?? 0,
                address: p?.address ?? '',
                emergencyContactId: p?.emergencyContactId,
                medicalCondition: p?.medicalCondition ?? '',
              )),
            ),
          ),
          _buildField(
            label: 'Address',
            value: (p?.address.isEmpty ?? true) ? 'Not set' : p!.address,
            onTap: () => _editText(
              title: 'Address',
              currentValue: p?.address ?? '',
              maxLines: 2,
              onSave: (v) => _saveProfile(Profile(
                name: p?.name ?? '',
                photoPath: p?.photoPath,
                gender: p?.gender ?? '',
                age: p?.age ?? 0,
                address: v,
                emergencyContactId: p?.emergencyContactId,
                medicalCondition: p?.medicalCondition ?? '',
              )),
            ),
          ),
          _buildField(
            label: 'Emergency Contact',
            value: _contactName(p?.emergencyContactId),
            onTap: _pickEmergencyContact,
          ),
          _buildField(
            label: 'Medical Condition',
            value: (p?.medicalCondition.isEmpty ?? true)
                ? 'Not set'
                : p!.medicalCondition,
            onTap: () => _editText(
              title: 'Medical Condition',
              currentValue: p?.medicalCondition ?? '',
              maxLines: 3,
              onSave: (v) => _saveProfile(Profile(
                name: p?.name ?? '',
                photoPath: p?.photoPath,
                gender: p?.gender ?? '',
                age: p?.age ?? 0,
                address: p?.address ?? '',
                emergencyContactId: p?.emergencyContactId,
                medicalCondition: v,
              )),
            ),
          ),
        ],
      ),
    );
  }

  // ===== CAREGIVER SECTION =====

  Widget _buildCaregiverSection() {
    final c = _caregiver;
    return _buildCard(
      title: 'Caregiver',
      titleIcon: Icons.medical_services,
      child: Column(
        children: [
          _buildPhoto(
            photoPath: c?.photoPath,
            onTap: () => _pickPhoto(isProfile: false),
          ),
          const SizedBox(height: 12),
          _buildField(
            label: 'Name',
            value: c?.name ?? 'Not set',
            onTap: () => _editText(
              title: 'Caregiver Name',
              currentValue: c?.name ?? '',
              onSave: (v) => _saveCaregiver(Caregiver(
                name: v,
                photoPath: c?.photoPath,
                age: c?.age ?? 0,
                address: c?.address ?? '',
                phone: c?.phone ?? '',
                relationship: c?.relationship ?? '',
              )),
            ),
          ),
          _buildField(
            label: 'Age',
            value: (c?.age ?? 0) == 0 ? 'Not set' : '${c!.age}',
            onTap: () => _editText(
              title: 'Caregiver Age',
              currentValue: (c?.age ?? 0) == 0 ? '' : '${c!.age}',
              keyboardType: TextInputType.number,
              onSave: (v) => _saveCaregiver(Caregiver(
                name: c?.name ?? '',
                photoPath: c?.photoPath,
                age: int.tryParse(v) ?? 0,
                address: c?.address ?? '',
                phone: c?.phone ?? '',
                relationship: c?.relationship ?? '',
              )),
            ),
          ),
          _buildField(
            label: 'Address',
            value: (c?.address.isEmpty ?? true) ? 'Not set' : c!.address,
            onTap: () => _editText(
              title: 'Caregiver Address',
              currentValue: c?.address ?? '',
              maxLines: 2,
              onSave: (v) => _saveCaregiver(Caregiver(
                name: c?.name ?? '',
                photoPath: c?.photoPath,
                age: c?.age ?? 0,
                address: v,
                phone: c?.phone ?? '',
                relationship: c?.relationship ?? '',
              )),
            ),
          ),
          _buildField(
            label: 'Phone Number',
            value: (c?.phone.isEmpty ?? true) ? 'Not set' : c!.phone,
            onTap: () => _editText(
              title: 'Caregiver Phone',
              currentValue: c?.phone ?? '',
              keyboardType: TextInputType.phone,
              onSave: (v) => _saveCaregiver(Caregiver(
                name: c?.name ?? '',
                photoPath: c?.photoPath,
                age: c?.age ?? 0,
                address: c?.address ?? '',
                phone: v,
                relationship: c?.relationship ?? '',
              )),
            ),
          ),
          _buildField(
            label: 'Relationship',
            value: (c?.relationship.isEmpty ?? true)
                ? 'Not set'
                : c!.relationship,
            onTap: () => _editText(
              title: 'Relationship',
              currentValue: c?.relationship ?? '',
              onSave: (v) => _saveCaregiver(Caregiver(
                name: c?.name ?? '',
                photoPath: c?.photoPath,
                age: c?.age ?? 0,
                address: c?.address ?? '',
                phone: c?.phone ?? '',
                relationship: v,
              )),
            ),
          ),
        ],
      ),
    );
  }

  // ===== HR SECTION =====

  Widget _buildHrSection() {
    final latest = _latestHr;
    return _buildCard(
      title: 'Heart Rate Recording',
      titleIcon: Icons.favorite,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (latest != null) ...[
            Center(
              child: Column(
                children: [
                  Text(
                    '${latest.avgBpm.toStringAsFixed(0)} BPM',
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: Colors.red[700],
                    ),
                  ),
                  Text(
                    'Latest reading · ${_formatDate(latest.timestamp)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$_hrSessionCount session${_hrSessionCount == 1 ? '' : 's'} recorded',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ] else ...[
            Center(
              child: Text(
                'No HR recordings yet',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ),
            const SizedBox(height: 16),
          ],
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _openHrRecorder,
              icon: const Icon(Icons.fiber_manual_record),
              label: const Text(
                'Record HR (60s)',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[700],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===== REUSABLE WIDGETS =====

  Widget _buildCard({
    required String title,
    required IconData titleIcon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(titleIcon, size: 20, color: Colors.indigo[700]),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildPhoto({
    required String? photoPath,
    required VoidCallback onTap,
  }) {
    return Center(
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey[200],
                border: Border.all(color: Colors.grey[400]!, width: 2),
              ),
              child: ClipOval(
                child: (photoPath != null && File(photoPath).existsSync())
                    ? Image.file(
                        File(photoPath),
                        width: 100,
                        height: 100,
                        fit: BoxFit.cover,
                      )
                    : Icon(
                        Icons.person,
                        size: 60,
                        color: Colors.grey[500],
                      ),
              ),
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.indigo[700],
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(
                  Icons.camera_alt,
                  size: 14,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 15,
                      color: Colors.black87,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.edit, size: 16, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
          '${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}