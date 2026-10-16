import 'package:flutter/material.dart';

import '../../widgets/permission_setup_panel.dart';

/// Permissions management from More — same layout as onboarding.
class PermissionsSettingsScreen extends StatefulWidget {
  const PermissionsSettingsScreen({super.key});

  @override
  State<PermissionsSettingsScreen> createState() =>
      _PermissionsSettingsScreenState();
}

class _PermissionsSettingsScreenState extends State<PermissionsSettingsScreen> {
  final GlobalKey<PermissionSetupPanelState> _panelKey =
      GlobalKey<PermissionSetupPanelState>();
  bool _refreshing = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F1FB),
      body: SafeArea(
        child: Column(
          children: [
            // ---------- TOP BAR ----------
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Row(
                children: [
                  Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      customBorder: const CircleBorder(),
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(
                          Icons.arrow_back_rounded,
                          size: 20,
                          color: Color(0xFF1F2330),
                        ),
                      ),
                    ),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text(
                        'Permissions',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1F2330),
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: _refreshing
                        ? const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF6F39E8),
                              ),
                            ),
                          )
                        : IconButton(
                            onPressed: () =>
                                _panelKey.currentState?.refreshAll(),
                            icon: const Icon(
                              Icons.refresh_rounded,
                              size: 20,
                              color: Color(0xFF6F39E8),
                            ),
                            tooltip: 'Refresh status',
                          ),
                  ),
                ],
              ),
            ),

            // ---------- HERO INTRO ----------
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF8F6FE), Color(0xFFEDE8FB)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFE7E4F1)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF6F39E8)
                                .withValues(alpha: 0.10),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.shield_moon_outlined,
                        color: Color(0xFF6F39E8),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your privacy, your control',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1F2330),
                              letterSpacing: -0.2,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Enable the permissions below so MindSync can '
                            'track usage and run face verification.',
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.35,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF6D6F7A),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ---------- SECTION HEADER ----------
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'REQUIRED PERMISSIONS',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.3,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF6F39E8),
                  ),
                ),
              ),
            ),

            // ---------- PERMISSION PANEL ----------
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                children: [
                  PermissionSetupPanel(
                    key: _panelKey,
                    onRefreshingChanged: (v) {
                      if (mounted) setState(() => _refreshing = v);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}