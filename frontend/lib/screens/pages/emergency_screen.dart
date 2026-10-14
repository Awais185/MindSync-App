import 'package:flutter/material.dart';
import '../../services/community_service.dart';
import '../../services/plan_access_service.dart';
import 'doctor_chat_screen.dart';

class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  final _service = CommunityService();
  bool _loading = false;
  List<TrustedContactItem> _contacts = const [];
  List<DoctorItem> _doctors = const [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final canUseDoctorContact = await PlanAccessService.instance.canAccess(
      'chat_digital_psychologist',
      forceRefresh: true,
    );
    final contacts = await _service.fetchTrustedContacts();
    final doctors = canUseDoctorContact ? await _service.fetchDoctors() : const <DoctorItem>[];
    if (!mounted) return;
    setState(() {
      _contacts = contacts;
      _doctors = doctors;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
          children: [
            // Header
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Emergency',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF161820),
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Warning Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFFFECEC),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFFECACA), width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: Color(0xFFDC2626),
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Need immediate help?',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF991B1B),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'If you are in danger or having a severe crisis, contact emergency services immediately. You are not alone.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF7F1D1D),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Call Emergency Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: () => _makeEmergencyCall(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
                icon: const Icon(Icons.call, size: 20),
                label: const Text(
                  'Call Emergency Services',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Trusted Contacts Section
            Row(
              children: [
                const Text(
                  'Trusted Contacts',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF161820),
                    letterSpacing: -0.3,
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: _showAddTrustedContactDialog,
                  child: const Text(
                  'ADD',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6F39E8),
                    letterSpacing: 0.5,
                  ),
                ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Contact List
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_contacts.isEmpty)
              const Text(
                'No trusted contacts yet. Tap ADD to create one.',
                style: TextStyle(fontSize: 12, color: Color(0xFF7E8090)),
              )
            else
              ..._contacts.map(
                (c) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _Contact(
                    name: c.name,
                    relation: c.relationship,
                    phone: c.contactNumber,
                  ),
                ),
              ),
            const SizedBox(height: 24),

            const Text(
              'Available Doctors / Psychologists',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF161820),
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 12),
            if (_doctors.isEmpty)
              const Text(
                'No doctor profiles found. Add from admin panel.',
                style: TextStyle(fontSize: 12, color: Color(0xFF7E8090)),
              )
            else
              ..._doctors.map(
                (d) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _DoctorTile(
                    doctor: d,
                    onOpenChat: () => _openDoctorChat(d),
                  ),
                ),
              ),
            const SizedBox(height: 24),

            // Breathing Exercise Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF6F39E8).withOpacity(0.1),
                    const Color(0xFF0E9186).withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: const Color(0xFF6F39E8).withOpacity(0.2),
                ),
              ),
              child: Column(
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.self_improvement,
                        size: 22,
                        color: Color(0xFF6F39E8),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Grounding Exercise',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF161820),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'You are not alone. Breathe in for 4 seconds, hold for 4, and exhale for 6. Repeat 5 times.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF525563),
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  _buildBreathingButton(context),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Additional Resources
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Additional Resources',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF161820),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildResourceItem(
                    icon: Icons.phone_in_talk,
                    title: 'Crisis Helpline',
                    subtitle: '24/7 Support Available',
                    color: const Color(0xFF6F39E8),
                  ),
                  const SizedBox(height: 10),
                  _buildResourceItem(
                    icon: Icons.chat_bubble_outline,
                    title: 'Text Support',
                    subtitle: 'Text HOME to 741741',
                    color: const Color(0xFF0E9186),
                  ),
                  const SizedBox(height: 10),
                  _buildResourceItem(
                    icon: Icons.health_and_safety,
                    title: 'Find a Therapist',
                    subtitle: 'Search for mental health professionals',
                    color: const Color(0xFF0058BE),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBreathingButton(BuildContext context) {
    return GestureDetector(
      onTap: () => _showBreathingGuide(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6F39E8), Color(0xFF8455EF)],
          ),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6F39E8).withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_circle, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text(
              'Start Breathing Exercise',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResourceItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF161820),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF8F919C),
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, size: 20, color: Color(0xFFC5C6D0)),
        ],
      ),
    );
  }

  void _makeEmergencyCall(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Emergency Call',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        content: const Text(
          'Are you sure you want to call emergency services?',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(
                color: Color(0xFF8B8D98),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Calling emergency services...'),
                  duration: Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: Color(0xFFDC2626),
                ),
              );
            },
            child: const Text(
              'Call Now',
              style: TextStyle(
                color: Color(0xFFDC2626),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showBreathingGuide(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      backgroundColor: Colors.white,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E5EA),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Box Breathing Exercise',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF161820),
              ),
            ),
            const SizedBox(height: 16),
            _buildBreathingStep('Inhale', '4 seconds', Icons.air),
            _buildBreathingStep('Hold', '4 seconds', Icons.pause),
            _buildBreathingStep('Exhale', '6 seconds', Icons.air),
            _buildBreathingStep('Hold', '2 seconds', Icons.pause),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6F39E8),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text(
                  'Start Exercise',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _openDoctorChat(DoctorItem doctor) async {
    final allowed = await PlanAccessService.instance.canAccess(
      'chat_digital_psychologist',
      forceRefresh: true,
    );
    if (!allowed) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Upgrade your plan to access this feature.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DoctorChatScreen(doctor: doctor)),
    );
  }

  Widget _buildBreathingStep(String action, String duration, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6FA),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF6F39E8).withOpacity(0.1),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(icon, color: const Color(0xFF6F39E8), size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF161820),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  duration,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8F919C),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: const Color(0xFF6F39E8),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddTrustedContactDialog() async {
    final name = TextEditingController();
    final relation = TextEditingController();
    final phone = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Trusted Contact'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
            TextField(
              controller: relation,
              decoration: const InputDecoration(labelText: 'Relationship'),
            ),
            TextField(
              controller: phone,
              decoration: const InputDecoration(labelText: 'Contact Number'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              final ok = await _service.createTrustedContact(
                name: name.text,
                relationship: relation.text,
                contactNumber: phone.text,
              );
              if (!mounted) return;
              navigator.pop();
              if (ok) _loadData();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _Contact extends StatelessWidget {
  const _Contact({
    required this.name,
    required this.relation,
    required this.phone,
  });

  final String name, relation, phone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFF0EBFF),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(Icons.person, size: 24, color: Color(0xFF6F39E8)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF161820),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$relation • $phone',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF7E8090),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5F2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: IconButton(
              onPressed: () => _makeCall(context, name, phone),
              icon: const Icon(Icons.call, size: 20, color: Color(0xFF0E9186)),
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }

  void _makeCall(BuildContext context, String name, String phone) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Call $name'),
        content: Text('Would you like to call $name at $phone?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Calling $name...'),
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: const Color(0xFF0E9186),
                ),
              );
            },
            child: const Text('Call'),
          ),
        ],
      ),
    );
  }
}

class _DoctorTile extends StatelessWidget {
  const _DoctorTile({
    required this.doctor,
    required this.onOpenChat,
  });

  final DoctorItem doctor;
  final VoidCallback onOpenChat;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onOpenChat,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(23),
              ),
              child: const Icon(Icons.medical_services_rounded, color: Color(0xFF0058BE)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doctor.fullName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF161820),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${doctor.designation} • ${doctor.experienceYears} yrs • ${doctor.specialist}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF7E8090)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    doctor.contactNumber,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF7E8090)),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF6F39E8)),
          ],
        ),
      ),
    );
  }
}
