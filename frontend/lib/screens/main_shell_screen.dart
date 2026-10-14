import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tabs/analytics_screen.dart';
import 'tabs/chat_screen.dart';
import 'tabs/home_screen.dart';
import 'tabs/more_screen.dart';
import 'tabs/parent_screen.dart';
import '../services/parental_control_service.dart';

class MainShellScreen extends StatefulWidget {
  const MainShellScreen({super.key, this.initialTab = 0});

  static const String shellTabPrefsKey = 'mindsync.shell_tab_index';

  final int initialTab;

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  static const _pages = <Widget>[
    HomeScreen(),
    AnalyticsScreen(),
    ParentScreen(),
    ChatScreen(),
    MoreScreen(),
  ];

  late int selectedTab;

  @override
  void initState() {
    super.initState();
    final tab = widget.initialTab;
    selectedTab = tab < 0
        ? 0
        : tab > 4
            ? 4
            : tab;
    _restoreSavedTab();
    ParentalControlService().syncInstalledApps();
  }

  Future<void> _restoreSavedTab() async {
    if (widget.initialTab != 0) return;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt(MainShellScreen.shellTabPrefsKey);
    if (!mounted || saved == null) return;
    if (saved < 0 || saved > 4) return;
    setState(() => selectedTab = saved);
  }

  Future<void> _onTabSelected(int value) async {
    setState(() => selectedTab = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(MainShellScreen.shellTabPrefsKey, value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: selectedTab,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedTab,
        onDestinationSelected: _onTabSelected,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.auto_graph), label: 'Analytics'),
          NavigationDestination(icon: Icon(Icons.groups), label: 'Parent'),
          NavigationDestination(icon: Icon(Icons.chat), label: 'Chat'),
          NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
        ],
      ),
    );
  }
}
