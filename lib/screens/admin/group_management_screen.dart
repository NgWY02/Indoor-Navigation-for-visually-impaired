import 'package:flutter/material.dart';
import '../../services/supabase_service.dart';

class GroupManagementScreen extends StatefulWidget {
  const GroupManagementScreen({Key? key}) : super(key: key);

  @override
  State<GroupManagementScreen> createState() => _GroupManagementScreenState();
}

class _GroupManagementScreenState extends State<GroupManagementScreen> {
  final SupabaseService _supabase = SupabaseService();
  final TextEditingController _groupNameController = TextEditingController();
  bool _busy = false;
  final TextEditingController _inviteCodeController = TextEditingController();
  List<Map<String, dynamic>> _myGroups = [];
  List<Map<String, dynamic>> _members = [];
  String? _selectedGroupId;

  @override
  void dispose() {
    _groupNameController.dispose();
    _inviteCodeController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    try {
      final groups = await _supabase.getGroupsICreated();
      setState(() {
        _myGroups = groups;
        if (_selectedGroupId == null && _myGroups.isNotEmpty) {
          _selectedGroupId = _myGroups.first['id'] as String?;
          if (_selectedGroupId != null) {
            _loadMembers(_selectedGroupId!);
          }
        }
      });
    } catch (_) {}
  }

  Future<void> _loadMembers(String groupId) async {
    try {
      final rows = await _supabase.getGroupMembersWithProfiles(groupId);
      setState(() => _members = rows);
    } catch (_) {}
  }

  Future<void> _createGroup() async {
    final name = _groupNameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    try {
      final id = await _supabase.createGroup(name: name);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Group created: $name')),
      );
      _groupNameController.clear();
      await _loadGroups();
      setState(() => _selectedGroupId = id);
      _loadMembers(id);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomSafe = mediaQuery.padding.bottom;
    final hasBottomNav = bottomSafe > 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Manage Groups')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: hasBottomNav ? 32 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Your Groups', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              if (_myGroups.isEmpty)
                const Text('No groups yet.'),
              for (final g in _myGroups) ...[
                Card(
                  shape: RoundedRectangleBorder(
                    side: BorderSide(
                      color: _selectedGroupId == g['id'] ? Theme.of(context).colorScheme.primary : Colors.transparent,
                      width: 1.2,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListTile(
                    title: Text(g['name'] ?? ''),
                    subtitle: Text('ID: ${g['id'].toString().substring(0, 8)}…'),
                    trailing: Icon(
                      _selectedGroupId == g['id'] ? Icons.check_circle : Icons.people_outline,
                      color: _selectedGroupId == g['id'] ? Theme.of(context).colorScheme.primary : null,
                    ),
                    onTap: () {
                      setState(() => _selectedGroupId = g['id']);
                      _loadMembers(g['id']);
                    },
                  ),
                ),
              ],
              if (_members.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Group Members', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                ..._members.map((m) => Card(
                      child: ListTile(
                        title: Text(m['email'] ?? m['name'] ?? m['user_id']),
                        subtitle: Text('Role: ${m['role']} • Code: ${m['user_code'] ?? '-'}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.remove_circle, color: Colors.red),
                          onPressed: () async {
                            final gid = _selectedGroupId;
                            if (gid == null) return;
                            await _supabase.removeMemberFromGroup(groupId: gid, userId: m['user_id']);
                            _loadMembers(gid);
                          },
                        ),
                      ),
                    )),
              ],
              const Divider(height: 32),
              const Text('Create a new group', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _groupNameController,
                decoration: const InputDecoration(
                  labelText: 'Group name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _busy ? null : _createGroup,
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.add),
                label: const Text('Create'),
              ),
              const Divider(height: 32),
              const Text('Invite by user code', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Selected group: ', style: TextStyle(fontWeight: FontWeight.w600)),
                  Expanded(
                    child: Text(
                      _selectedGroupId == null
                          ? 'None'
                          : _myGroups.firstWhere(
                                (g) => g['id'] == _selectedGroupId,
                                orElse: () => {'name': 'Unknown'},
                              )['name'] ?? 'Unknown',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _inviteCodeController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'User Code (e.g., ABC123)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: () async {
                  final gid = _selectedGroupId;
                  final ucode = _inviteCodeController.text.trim().toUpperCase();
                  if (gid == null || gid.isEmpty || ucode.isEmpty) return;
                  setState(() => _busy = true);
                  try {
                    await _supabase.addUserToGroupByCode(groupId: gid, userCode: ucode);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('User added to group')),
                    );
                    await _loadMembers(gid);
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.person_add_alt),
                label: const Text('Add to Group'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


