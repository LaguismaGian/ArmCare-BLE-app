import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../backend/database_service.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<Contact> _contacts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    setState(() => _isLoading = true);
    final list = await DatabaseService.instance.getAllContacts();
    if (!mounted) return;
    setState(() {
      _contacts = list;
      _isLoading = false;
    });
  }

  // ===== CALL =====

  Future<void> _callContact(Contact contact) async {
    final cleaned = contact.phone.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri(scheme: 'tel', path: cleaned);

    try {
      final launched = await launchUrl(uri);
      if (!launched && mounted) {
        _showSnack('Could not open dialer');
      }
    } catch (e) {
      if (mounted) _showSnack('Call failed: $e');
    }
  }

  // ===== DELETE =====

  Future<void> _deleteContact(Contact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Contact?'),
        content: Text('Remove "${contact.name}" from emergency contacts?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true && contact.id != null) {
      await DatabaseService.instance.deleteContact(contact.id!);
      _loadContacts();
      if (mounted) _showSnack('Contact removed');
    }
  }

  // ===== ADD =====

  Future<void> _showAddSheet() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _AddContactSheet(
        onSaved: () {
          Navigator.pop(context);
          _loadContacts();
        },
      ),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  // ===== BUILD =====

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Emergency Contacts'),
        backgroundColor: Colors.red[700],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddSheet,
            tooltip: 'Add Contact',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _contacts.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _contacts.length,
                  itemBuilder: (context, index) =>
                      _buildContactCard(_contacts[index]),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.contact_phone_outlined,
                size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No emergency contacts yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the + button to add someone\nyou can call in an emergency.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactCard(Contact contact) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.red[100],
              child: Icon(Icons.person, color: Colors.red[700]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contact.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    contact.phone,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.phone, color: Colors.green[700]),
              onPressed: () => _callContact(contact),
              tooltip: 'Call',
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: () => _deleteContact(contact),
              tooltip: 'Remove',
            ),
          ],
        ),
      ),
    );
  }
}

// =====================
// ADD CONTACT BOTTOM SHEET
// =====================

class _AddContactSheet extends StatefulWidget {
  final VoidCallback onSaved;

  const _AddContactSheet({required this.onSaved});

  @override
  State<_AddContactSheet> createState() => _AddContactSheetState();
}

class _AddContactSheetState extends State<_AddContactSheet> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  bool _isPickingContact = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  // ===== PICK FROM PHONE CONTACTS =====

  Future<void> _pickFromPhone() async {
    setState(() => _isPickingContact = true);

    try {
      final status = await Permission.contacts.request();

      if (!status.isGranted) {
        setState(() => _isPickingContact = false);
        if (mounted) _showSnack('Contacts permission denied');
        return;
      }

      final contacts = await fc.FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: false,
      );

      if (!mounted) return;
      setState(() => _isPickingContact = false);

      if (contacts.isEmpty) {
        _showSnack('No contacts found on this phone');
        return;
      }

      final picked = await showModalBottomSheet<_PickedContact>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) => _PhoneContactPicker(contacts: contacts),
      );

      if (picked != null && mounted) {
        _nameCtrl.text = picked.name;
        _phoneCtrl.text = picked.phone;
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isPickingContact = false);
        _showSnack('Failed to read contacts: $e');
      }
    }
  }

  // ===== SAVE =====

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();

    if (name.isEmpty || phone.isEmpty) {
      _showSnack('Please fill in both name and phone');
      return;
    }

    await DatabaseService.instance.insertContact(
      Contact(name: name, phone: phone),
    );

    widget.onSaved();
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: 20 + bottomInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Add Emergency Contact',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _isPickingContact ? null : _pickFromPhone,
              icon: _isPickingContact
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.contacts),
              label: Text(
                _isPickingContact
                    ? 'Loading...'
                    : 'Pick from Phone Contacts',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.blue[700],
                side: BorderSide(color: Colors.blue[300]!),
              ),
            ),
          ),

          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'or enter manually',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ),
              const Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone Number',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.phone_outlined),
              hintText: '+63 912 345 6789',
            ),
          ),
          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[700],
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// =====================
// SIMPLE "PICKED CONTACT" HOLDER
// =====================

/// A lightweight wrapper so the picker can return a name+phone pair
/// without importing the flutter_contacts Contact type everywhere.
class _PickedContact {
  final String name;
  final String phone;
  _PickedContact({required this.name, required this.phone});
}

// =====================
// PHONE CONTACT PICKER
// =====================

class _PhoneContactPicker extends StatefulWidget {
  final List<fc.Contact> contacts;

  const _PhoneContactPicker({required this.contacts});

  @override
  State<_PhoneContactPicker> createState() => _PhoneContactPickerState();
}

class _PhoneContactPickerState extends State<_PhoneContactPicker> {
  final TextEditingController _searchCtrl = TextEditingController();
  late List<fc.Contact> _filtered;

  @override
  void initState() {
    super.initState();
    _filtered = widget.contacts;
    _searchCtrl.addListener(_onSearch);
  }

  void _onSearch() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = widget.contacts.where((c) {
        return c.displayName.toLowerCase().contains(q) ||
            c.phones.any((p) => p.number.contains(q));
      }).toList();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  hintText: 'Search contacts...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _filtered.isEmpty
                  ? const Center(child: Text('No contacts match'))
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: _filtered.length,
                      itemBuilder: (context, index) {
                        final c = _filtered[index];
                        final phone = c.phones.isNotEmpty
                            ? c.phones.first.number
                            : '(no number)';

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.blue[100],
                            child: Text(
                              c.displayName.isNotEmpty
                                  ? c.displayName[0].toUpperCase()
                                  : '?',
                              style: TextStyle(color: Colors.blue[800]),
                            ),
                          ),
                          title: Text(c.displayName),
                          subtitle: Text(phone),
                          enabled: c.phones.isNotEmpty,
                          onTap: c.phones.isEmpty
                              ? null
                              : () => Navigator.pop(
                                    context,
                                    _PickedContact(
                                      name: c.displayName,
                                      phone: phone,
                                    ),
                                  ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}