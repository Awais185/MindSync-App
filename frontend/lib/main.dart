import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'config/api_config.dart';
import 'utils/stripe_platform.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    await initializeStripePublishableKey();
  }
  await ApiConfig.initialize();
  // Authentication uses Django SQL via LocalAuthService (not Firebase).
  runApp(const MindSyncApp());
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.onGetStarted});

  final VoidCallback onGetStarted;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFECE7F8),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            children: [
              const Spacer(),
              Container(
                height: 130,
                width: 130,
                decoration: BoxDecoration(
                  color: Colors.white70,
                  borderRadius: BorderRadius.circular(34),
                ),
                child: const Center(
                  child: CircleAvatar(
                    radius: 32,
                    backgroundColor: Color(0xFF6F39E8),
                    child: Icon(Icons.psychology, color: Colors.white, size: 32),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'MindSync',
                style: TextStyle(
                  fontSize: 46,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF6F39E8),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'AI-Powered Emotional Wellness',
                style: TextStyle(fontSize: 20, color: Color(0xFF6B6B75)),
              ),
              const SizedBox(height: 32),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white70,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.auto_awesome, color: Color(0xFF3F70DA)),
                        SizedBox(width: 8),
                        Text(
                          'PERSONALIZED INSIGHT',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                            color: Color(0xFF2E5EB7),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    Text(
                      '"The first step towards wellness is understanding the rhythm of your heart and mind."',
                      style: TextStyle(fontSize: 21, height: 1.35),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 62,
                child: ElevatedButton(
                  onPressed: () {
                    onGetStarted();
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    foregroundColor: Colors.white,
                    backgroundColor: const Color(0xFF6F39E8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Get Started',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 10),
                      Icon(Icons.arrow_forward, size: 28),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'By continuing, you agree to our Terms of Service',
                style: TextStyle(color: Color(0xFF8D8D97)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              const Center(
                child: CircleAvatar(
                  radius: 34,
                  backgroundColor: Color(0xFF6F39E8),
                  child: Icon(Icons.psychology, color: Colors.white, size: 36),
                ),
              ),
              const SizedBox(height: 20),
              const Center(
                child: Text(
                  'MindSync',
                  style: TextStyle(
                    fontSize: 50,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF6F39E8),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Center(
                child: Text(
                  'The Sanctuary for your Mind',
                  style: TextStyle(fontSize: 18, color: Color(0xFF7D7D87)),
                ),
              ),
              const SizedBox(height: 30),
              const _InputBox(hint: 'Email Address'),
              const SizedBox(height: 14),
              const _InputBox(hint: 'Password', obscure: true),
              const SizedBox(height: 12),
              Row(
                children: [
                  Checkbox(value: false, onChanged: (_) {}),
                  const Text('Remember me'),
                  const Spacer(),
                  TextButton(
                    onPressed: () {},
                    child: const Text(
                      'Forgot password?',
                      style: TextStyle(
                        color: Color(0xFF6F39E8),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const MainShellScreen()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: const Color(0xFF6F39E8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: const Text(
                    'Login',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    child: Text('OR CONTINUE WITH'),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 20),
              _SocialButton(
                label: 'Google',
                background: Colors.white,
                textColor: Colors.black87,
              ),
              const SizedBox(height: 12),
              _SocialButton(
                label: 'Apple',
                background: const Color(0xFF10151C),
                textColor: Colors.white,
              ),
              const SizedBox(height: 20),
              Center(
                child: TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SignupScreen()),
                    );
                  },
                  child: const Text(
                    'Create account',
                    style: TextStyle(
                      color: Color(0xFF6F39E8),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SignupScreen extends StatelessWidget {
  const SignupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'MindSync',
                style: TextStyle(
                  fontSize: 38,
                  color: Color(0xFF6F39E8),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Text(
                'Begin your journey to a luminous mind.',
                style: TextStyle(fontSize: 17, color: Color(0xFF66666F)),
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  children: [
                    const CircleAvatar(
                      radius: 32,
                      backgroundColor: Color(0xFFDACEF6),
                      child: Icon(
                        Icons.fingerprint,
                        color: Color(0xFF6F39E8),
                        size: 34,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'FACE ENROLLMENT',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'For secure, hands-free entry',
                      style: TextStyle(color: Color(0xFF6D6D78)),
                    ),
                    const SizedBox(height: 18),
                    const _InputBox(hint: 'Full Name'),
                    const SizedBox(height: 12),
                    const _InputBox(hint: 'Select Profession'),
                    const SizedBox(height: 12),
                    const _InputBox(hint: 'Email Address'),
                    const SizedBox(height: 12),
                    const _InputBox(hint: 'Password', obscure: true),
                    const SizedBox(height: 12),
                    const _InputBox(hint: 'Confirm Password', obscure: true),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Checkbox(value: false, onChanged: (_) {}),
                        const Expanded(
                          child: Text('I agree to the Terms of Sanctuary'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => const MainShellScreen(),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: const Color(0xFF6F39E8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(26),
                          ),
                        ),
                        child: const Text(
                          'Create Account',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SocialButton(
                      label: 'Google',
                      background: Colors.white,
                      textColor: Colors.black87,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Already have an account?'),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          child: const Text(
                            'Login',
                            style: TextStyle(
                              color: Color(0xFF6F39E8),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MainShellScreen extends StatefulWidget {
  const MainShellScreen({super.key});

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  int selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const HomeScreen(),
      const AnalyticsScreen(),
      const ParentScreen(),
      const ChatScreen(),
      const MoreScreen(),
    ];
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6FA),
      body: pages[selectedTab],
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: const [
              BoxShadow(
                color: Color(0x11000000),
                blurRadius: 14,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _BottomItem(
                icon: Icons.home_rounded,
                label: 'HOME',
                isActive: selectedTab == 0,
                onTap: () => setState(() => selectedTab = 0),
              ),
              _BottomItem(
                icon: Icons.auto_graph_rounded,
                label: '',
                isActive: selectedTab == 1,
                highlighted: selectedTab == 1,
                onTap: () => setState(() => selectedTab = 1),
              ),
              _BottomItem(
                icon: Icons.groups_rounded,
                label: 'PARENT',
                isActive: selectedTab == 2,
                onTap: () => setState(() => selectedTab = 2),
              ),
              _BottomItem(
                icon: Icons.chat_bubble_outline_rounded,
                label: 'CHAT',
                isActive: selectedTab == 3,
                onTap: () => setState(() => selectedTab = 3),
              ),
              _BottomItem(
                icon: Icons.more_horiz_rounded,
                label: 'MORE',
                isActive: selectedTab == 4,
                onTap: () => setState(() => selectedTab = 4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6FA),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 86),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              const Text(
                'Hello, Alex',
                style: TextStyle(
                  color: Color(0xFF1E2432),
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              const Row(
                children: [
                  Icon(Icons.eco, color: Color(0xFF1DC19E), size: 13),
                  SizedBox(width: 5),
                  Text(
                    'Your mind is in a restorative phase today',
                    style: TextStyle(
                      color: Color(0xFF5C927F),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: const [
                  Expanded(child: _HomeTopLeftCard()),
                  SizedBox(width: 9),
                  Expanded(child: _HomeTopRightCard()),
                ],
              ),
              const SizedBox(height: 9),
              Row(
                children: const [
                  Expanded(child: _HomeBottomLeftCard()),
                  SizedBox(width: 9),
                  Expanded(child: _HomeBottomRightCard()),
                ],
              ),
              const SizedBox(height: 15),
              const _HomeAppUsageCard(),
              const SizedBox(height: 14),
              const _HomeVulnerabilityCard(),
              const SizedBox(height: 14),
              const _HomeMoodCard(),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeCardShell extends StatelessWidget {
  const _HomeCardShell({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: child,
    );
  }
}

class _HomeTopLeftCard extends StatelessWidget {
  const _HomeTopLeftCard();
  @override
  Widget build(BuildContext context) {
    return const _HomeCardShell(
      child: Column(
        children: [
          SizedBox(height: 3),
          _ScoreCircle(),
          SizedBox(height: 10),
          Text(
            'WELLBEING SCORE',
            style: TextStyle(
              fontSize: 8,
              letterSpacing: 1.3,
              color: Color(0xFF8A8D99),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeTopRightCard extends StatelessWidget {
  const _HomeTopRightCard();
  @override
  Widget build(BuildContext context) {
    return const _HomeCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.access_time_filled, size: 12, color: Color(0xFF456B7B)),
              Spacer(),
              Text(
                '+12%',
                style: TextStyle(
                  fontSize: 9,
                  color: Color(0xFF2C79D5),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          SizedBox(height: 6),
          Text(
            '4h 20m',
            style: TextStyle(fontSize: 26, height: 1, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 4),
          Text(
            'SCREEN TIME',
            style: TextStyle(
              fontSize: 8,
              letterSpacing: 1.2,
              color: Color(0xFF8A8D99),
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8),
          Align(alignment: Alignment.bottomRight, child: SizedBox(width: 42, height: 24, child: _TinyBars())),
        ],
      ),
    );
  }
}

class _HomeBottomLeftCard extends StatelessWidget {
  const _HomeBottomLeftCard();
  @override
  Widget build(BuildContext context) {
    return const _HomeCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.monitor_heart_outlined, size: 13, color: Color(0xFF27B1A2)),
          SizedBox(height: 8),
          Text('Medium', style: TextStyle(fontSize: 29, height: 1, fontWeight: FontWeight.w700)),
          SizedBox(height: 5),
          Text(
            'STRESS LEVEL',
            style: TextStyle(
              fontSize: 8,
              letterSpacing: 1.2,
              color: Color(0xFF8A8D99),
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 10),
          _MiniProgress(color: Color(0xFF19B6A6), value: 0.55),
        ],
      ),
    );
  }
}

class _HomeBottomRightCard extends StatelessWidget {
  const _HomeBottomRightCard();
  @override
  Widget build(BuildContext context) {
    return const _HomeCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.notifications_active, size: 13, color: Color(0xFFE05957)),
          SizedBox(height: 8),
          Text('2 Alerts', style: TextStyle(fontSize: 29, height: 1, fontWeight: FontWeight.w700)),
          SizedBox(height: 5),
          Text(
            'ACTION NEEDED',
            style: TextStyle(
              fontSize: 8,
              letterSpacing: 1.2,
              color: Color(0xFF8A8D99),
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 7),
          Text(
            '1 TikTok usage spike',
            style: TextStyle(fontSize: 8, color: Color(0xFFD95A5A), fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _HomeAppUsageCard extends StatelessWidget {
  const _HomeAppUsageCard();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
      child: const Column(
        children: [
          Row(
            children: [
              Text('App Usage', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, height: 1)),
              Spacer(),
              Text('TODAY', style: TextStyle(fontSize: 10, color: Color(0xFF8C8C96))),
            ],
          ),
          SizedBox(height: 12),
          _HomeUsageRow(label: 'TikTok', duration: '1h 45m', color: Color(0xFFE06C80), progress: 0.82),
          _HomeUsageRow(label: 'YouTube', duration: '55m', color: Color(0xFFD95A6A), progress: 0.46),
          _HomeUsageRow(label: 'Discord', duration: '42m', color: Color(0xFF626ED7), progress: 0.36),
        ],
      ),
    );
  }
}

class _HomeVulnerabilityCard extends StatelessWidget {
  const _HomeVulnerabilityCard();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Vulnerability Map', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, height: 1)),
              Spacer(),
              Icon(Icons.info_outline_rounded, color: Color(0xFF8F8F9A), size: 14),
            ],
          ),
          SizedBox(height: 12),
          _VulnerabilityRow(
            label: 'Stress',
            subtitle: 'Elevated due to screen density',
            value: '64%',
            progress: 0.64,
            color: Color(0xFF7E4AE7),
          ),
          _VulnerabilityRow(
            label: 'Anxiety',
            subtitle: 'Stable baseline',
            value: '22%',
            progress: 0.22,
            color: Color(0xFF1EB4A8),
          ),
          _VulnerabilityRow(
            label: 'Depression',
            subtitle: 'Optimal resilience',
            value: '12%',
            progress: 0.12,
            color: Color(0xFF2E6FD2),
          ),
        ],
      ),
    );
  }
}

class _HomeMoodCard extends StatelessWidget {
  const _HomeMoodCard();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Weekly Mood Architecture',
            style: TextStyle(fontSize: 31, fontWeight: FontWeight.w700, height: 1.02),
          ),
          const SizedBox(height: 4),
          const Text(
            '• POSITIVE TRAJECTORY',
            style: TextStyle(
              fontSize: 13,
              letterSpacing: 1.0,
              color: Color(0xFF37B48A),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Row(children: [_Pill(text: '7 Days'), SizedBox(width: 6), _Pill(text: '30 Days')]),
          const SizedBox(height: 12),
          const SizedBox(height: 132, child: _HomeMoodChart()),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              _ChartDay('MON'),
              _ChartDay('TUE'),
              _ChartDay('WED'),
              _ChartDay('THU'),
              _ChartDay('FRI'),
              _ChartDay('SAT'),
              _ChartDay('SUN'),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScoreCircle extends StatelessWidget {
  const _ScoreCircle();
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      height: 46,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: 0.78,
            strokeWidth: 3.2,
            backgroundColor: Color(0xFFE7E8F0),
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6F39E8)),
          ),
          Text('78', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
        ],
      ),
    );
  }
}

class _TinyBars extends StatelessWidget {
  const _TinyBars();
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          width: 6,
          height: 17,
          decoration: BoxDecoration(color: Color(0xFF6F39E8), borderRadius: BorderRadius.circular(4)),
        ),
        const SizedBox(width: 3),
        Container(
          width: 6,
          height: 22,
          decoration: BoxDecoration(color: Color(0xFF2E7CD8), borderRadius: BorderRadius.circular(4)),
        ),
      ],
    );
  }
}

class _MiniProgress extends StatelessWidget {
  const _MiniProgress({required this.color, required this.value});
  final Color color;
  final double value;
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 4,
        backgroundColor: Color(0xFFE6E7ED),
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }
}

class _HomeUsageRow extends StatelessWidget {
  const _HomeUsageRow({
    required this.label,
    required this.duration,
    required this.color,
    required this.progress,
  });
  final String label;
  final String duration;
  final Color color;
  final double progress;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.watch_later_outlined, size: 10, color: color),
              ),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
              const Spacer(),
              Text(duration, style: const TextStyle(fontSize: 12, color: Color(0xFF4D4D57))),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 3.8,
              backgroundColor: Color(0xFFE2E3E8),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

class _VulnerabilityRow extends StatelessWidget {
  const _VulnerabilityRow({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.progress,
    required this.color,
  });
  final String label;
  final String subtitle;
  final String value;
  final double progress;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          Row(
            children: [
              Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(
                value,
                style: const TextStyle(fontSize: 12, color: Color(0xFF385A76), fontWeight: FontWeight.w700),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Text(subtitle, style: const TextStyle(color: Color(0xFF9EA0AA), fontSize: 9.5)),
              ),
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: Color(0xFFE3E4EA),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: Color(0xFFF2F3F8), borderRadius: BorderRadius.circular(11)),
      child: Text(text, style: const TextStyle(fontSize: 9.5, color: Color(0xFF64646F))),
    );
  }
}

class _ChartDay extends StatelessWidget {
  const _ChartDay(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF7B7D87),
        fontSize: 8.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
      ),
    );
  }
}

class _HomeMoodChart extends StatelessWidget {
  const _HomeMoodChart();
  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _HomeMoodChartPainter(), child: const SizedBox.expand());
  }
}

class _HomeMoodChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final fillPath = Path();
    fillPath.moveTo(0, size.height * 0.88);
    fillPath.cubicTo(size.width * 0.18, size.height * 0.62, size.width * 0.26, size.height * 0.95, size.width * 0.4, size.height * 0.6);
    fillPath.cubicTo(size.width * 0.55, size.height * 0.25, size.width * 0.66, size.height * 0.93, size.width * 0.78, size.height * 0.44);
    fillPath.cubicTo(size.width * 0.88, size.height * 0.04, size.width * 0.95, size.height * 0.18, size.width, size.height * 0.18);
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();
    canvas.drawPath(fillPath, Paint()..color = const Color(0xFFECE8FB));

    final line = Path();
    line.moveTo(0, size.height * 0.88);
    line.cubicTo(size.width * 0.18, size.height * 0.62, size.width * 0.26, size.height * 0.95, size.width * 0.4, size.height * 0.6);
    line.cubicTo(size.width * 0.55, size.height * 0.25, size.width * 0.66, size.height * 0.93, size.width * 0.78, size.height * 0.44);
    line.cubicTo(size.width * 0.88, size.height * 0.04, size.width * 0.95, size.height * 0.18, size.width, size.height * 0.18);
    canvas.drawPath(
      line,
      Paint()
        ..color = const Color(0xFF6F39E8)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ParentScreen extends StatefulWidget {
  const ParentScreen({super.key});

  @override
  State<ParentScreen> createState() => _ParentScreenState();
}

class _ParentScreenState extends State<ParentScreen> {
  bool socialRestriction = true;
  bool gamingRestriction = true;
  bool entertainmentRestriction = false;
  bool tiktokRestriction = true;
  bool youtubeRestriction = true;
  bool robloxRestriction = false;
  bool safeSearch = false;
  bool blockAdult = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6FA),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 86),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: Color(0xFF333333),
                    child: Icon(Icons.person, size: 13, color: Colors.white),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Guardian Sanctuary',
                    style: TextStyle(
                      color: Color(0xFF5A5FCD),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Spacer(),
                  Icon(Icons.notifications, size: 14, color: Color(0xFF7A4FE8)),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'LIVE PROTECTION',
                style: TextStyle(
                  color: Color(0xFFA5A6B2),
                  fontSize: 9.5,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                "Monitoring Active:\nLeo's iPhone",
                style: TextStyle(
                  height: 1.06,
                  color: Color(0xFF15161D),
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  children: [
                    CircleAvatar(
                      radius: 13,
                      backgroundColor: Color(0xFFE8D8CA),
                      child: Icon(Icons.person, size: 14, color: Color(0xFF7A5036)),
                    ),
                    SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Leo Harrison',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                        Text(
                          '• Online Now',
                          style: TextStyle(color: Color(0xFF989AA6), fontSize: 9),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Column(
                  children: [
                    SizedBox(height: 4),
                    SizedBox(height: 124, child: _UsageHealthCircle()),
                    SizedBox(height: 8),
                    Text(
                      'Usage Health',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'Leo is 58% through his daily allowance.',
                      style: TextStyle(fontSize: 9.5, color: Color(0xFFA2A3AE)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const _ParentContentMonitorCard(),
              const SizedBox(height: 12),
              _ParentToggleCard(
                title: 'Content Time\nRestrictions',
                actionLabel: '',
                children: [
                  _ParentToggleRow(
                    iconBg: const Color(0xFFEADFFF),
                    iconColor: const Color(0xFF7A4FE8),
                    icon: Icons.groups_rounded,
                    title: 'Social Media',
                    subtitle: 'Limit: 1h 30m',
                    value: socialRestriction,
                    onChanged: (v) => setState(() => socialRestriction = v),
                  ),
                  _ParentToggleRow(
                    iconBg: const Color(0xFFE6F0FF),
                    iconColor: const Color(0xFF2E6FD2),
                    icon: Icons.sports_esports_rounded,
                    title: 'Gaming',
                    subtitle: 'Limit: 1h 00m',
                    value: gamingRestriction,
                    onChanged: (v) => setState(() => gamingRestriction = v),
                  ),
                  _ParentToggleRow(
                    iconBg: const Color(0xFFDDF7F4),
                    iconColor: const Color(0xFF0E9186),
                    icon: Icons.movie_rounded,
                    title: 'Entertainment',
                    subtitle: 'Limit: 2h 00m',
                    value: entertainmentRestriction,
                    onChanged: (v) => setState(() => entertainmentRestriction = v),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _ParentToggleCard(
                title: 'App Restrictions',
                actionLabel: 'View All +',
                children: [
                  _ParentToggleRow(
                    iconBg: Colors.black,
                    iconColor: Colors.white,
                    icon: Icons.music_note_rounded,
                    title: 'TikTok',
                    subtitle: '1hr 7 minutes used today',
                    limitLabel: 'Limit:\n45m',
                    value: tiktokRestriction,
                    onChanged: (v) => setState(() => tiktokRestriction = v),
                  ),
                  _ParentToggleRow(
                    iconBg: const Color(0xFFFCE3E2),
                    iconColor: const Color(0xFFCE2F2F),
                    icon: Icons.play_arrow_rounded,
                    title: 'YouTube',
                    subtitle: '2hr spent this week',
                    limitLabel: 'Limit:\n1h',
                    value: youtubeRestriction,
                    onChanged: (v) => setState(() => youtubeRestriction = v),
                  ),
                  _ParentToggleRow(
                    iconBg: const Color(0xFFDDEBFF),
                    iconColor: const Color(0xFF3D78D7),
                    icon: Icons.sports_esports_rounded,
                    title: 'Roblox',
                    subtitle: '25m',
                    limitLabel: 'Limit:\n30m',
                    value: robloxRestriction,
                    onChanged: (v) => setState(() => robloxRestriction = v),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _ParentToggleCard(
                title: 'Safety Controls',
                actionLabel: '',
                children: [
                  _ParentToggleRow(
                    iconBg: const Color(0xFFDDF7F4),
                    iconColor: const Color(0xFF0E9186),
                    icon: Icons.search_rounded,
                    title: 'SafeSearch Active',
                    subtitle: 'Filters explicit websites',
                    value: safeSearch,
                    onChanged: (v) => setState(() => safeSearch = v),
                  ),
                  _ParentToggleRow(
                    iconBg: const Color(0xFFEADFFF),
                    iconColor: const Color(0xFF6F39E8),
                    icon: Icons.block_rounded,
                    title: 'Block Adult Content',
                    subtitle: 'System-wide web filtering',
                    value: blockAdult,
                    onChanged: (v) => setState(() => blockAdult = v),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UsageHealthCircle extends StatelessWidget {
  const _UsageHealthCircle();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _UsageHealthPainter(),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '2h 45m',
              style: TextStyle(fontSize: 29, fontWeight: FontWeight.w800),
            ),
            Text(
              'OF 4H LIMIT',
              style: TextStyle(
                color: Color(0xFF8A8D99),
                fontSize: 9.5,
                letterSpacing: 1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UsageHealthPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.35;
    final track =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..color = const Color(0xFFE8E8EF)
          ..strokeCap = StrokeCap.round;
    final active =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..color = const Color(0xFF6F39E8)
          ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.75,
      5.2,
      false,
      track,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.75,
      3.1,
      false,
      active,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ParentContentMonitorCard extends StatelessWidget {
  const _ParentContentMonitorCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Column(
        children: [
          Row(
            children: [
              Text(
                'Content Monitor',
                style: TextStyle(fontSize: 29, fontWeight: FontWeight.w700),
              ),
              Spacer(),
              Icon(Icons.monitor_heart, color: Color(0xFF0FA096), size: 14),
            ],
          ),
          SizedBox(height: 10),
          _ContentBar(label: 'Education', value: '45%', progress: 0.45, color: Color(0xFF148C83)),
          _ContentBar(label: 'Social Media', value: '30%', progress: 0.30, color: Color(0xFF6F39E8)),
          _ContentBar(label: 'Gaming', value: '20%', progress: 0.20, color: Color(0xFF2E6FD2)),
          SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: _WarningPill(
                  icon: Icons.warning_amber_rounded,
                  text: 'Adult Sites\nBlocked',
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _WarningPill(
                  icon: Icons.warning_amber_rounded,
                  text: 'Violent\nContent\nBlocked',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ContentBar extends StatelessWidget {
  const _ContentBar({
    required this.label,
    required this.value,
    required this.progress,
    required this.color,
  });
  final String label;
  final String value;
  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                value,
                style: const TextStyle(
                  color: Color(0xFF55738D),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: const Color(0xFFE3E4EA),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningPill extends StatelessWidget {
  const _WarningPill({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5FA),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, size: 10, color: const Color(0xFFE05957)),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              fontSize: 8,
              color: Color(0xFFA45E5E),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ParentToggleCard extends StatelessWidget {
  const _ParentToggleCard({
    required this.title,
    required this.actionLabel,
    required this.children,
  });
  final String title;
  final String actionLabel;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 29, fontWeight: FontWeight.w700, height: 1.05),
              ),
              const Spacer(),
              if (actionLabel.isNotEmpty)
                Text(
                  actionLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF6F39E8),
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _ParentToggleRow extends StatelessWidget {
  const _ParentToggleRow({
    required this.iconBg,
    required this.iconColor,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.limitLabel,
  });

  final Color iconBg;
  final Color iconColor;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? limitLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 12, color: iconColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 8.5, color: Color(0xFFA0A2AE)),
                ),
              ],
            ),
          ),
          if (limitLabel != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(
                limitLabel!,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: Color(0xFF8A8D99),
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          SizedBox(
            width: 30,
            height: 18,
            child: FittedBox(
              fit: BoxFit.fill,
              child: Switch(
                value: value,
                onChanged: onChanged,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                activeThumbColor: Colors.white,
                activeTrackColor: const Color(0xFF6F39E8),
                inactiveThumbColor: Colors.white,
                inactiveTrackColor: const Color(0xFF0E9186),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6FA),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 86),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.spa, color: Color(0xFF6F39E8), size: 16),
                  SizedBox(width: 6),
                  Text(
                    'Sanctuary',
                    style: TextStyle(
                      color: Color(0xFF6F39E8),
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  Spacer(),
                  CircleAvatar(
                    radius: 13,
                    backgroundColor: Color(0xFF2A2A2A),
                    child: Icon(Icons.person, size: 14, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Row(
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 25,
                        backgroundColor: Color(0xFF2E3A4C),
                        child: Icon(Icons.person, color: Colors.white, size: 30),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: CircleAvatar(
                          radius: 9,
                          backgroundColor: Color(0xFF6F39E8),
                          child: Icon(Icons.edit, size: 9, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Elena Vance',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF15161D),
                ),
              ),
              const Text(
                'elena.vance@mindsync.io',
                style: TextStyle(fontSize: 11, color: Color(0xFF848692)),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF5E2EDF), Color(0xFF7A4FE8)],
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CURRENT TIER',
                            style: TextStyle(
                              color: Color(0xFFCEB9FF),
                              fontSize: 9,
                              letterSpacing: 1.3,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Premium\nMember',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 34,
                              height: 1.0,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Your sanctuary access\nexpires in 24 days.',
                            style: TextStyle(
                              color: Color(0xFFD9CBFF),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _RenewPill(),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'PERSONALIZATION',
                style: TextStyle(
                  color: Color(0xFF8B8D98),
                  letterSpacing: 2,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              _MoreMenuCard(
                icon: Icons.person,
                title: 'Profile',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  );
                },
              ),
              const SizedBox(height: 8),
              const _MoreMenuCard(icon: Icons.face_retouching_natural, title: 'Face Scan'),
              const SizedBox(height: 8),
              _MoreMenuCard(
                icon: Icons.auto_awesome,
                title: 'Upgrade Plan',
                subtitle: 'Basic • Standard • Premium',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const UpgradePlanScreen()),
                  );
                },
              ),
              const SizedBox(height: 8),
              const _MoreMenuCard(icon: Icons.phone_android, title: 'Screen Time'),
              const SizedBox(height: 10),
              const Text(
                'SUPPORT & GROWTH',
                style: TextStyle(
                  color: Color(0xFF8B8D98),
                  letterSpacing: 2,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              _MoreMenuCard(
                icon: Icons.emergency,
                title: 'Emergency',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const EmergencyScreen()),
                  );
                },
              ),
              const SizedBox(height: 8),
              _MoreMenuCard(
                icon: Icons.groups_rounded,
                title: 'Community',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CommunityScreen()),
                  );
                },
              ),
              const SizedBox(height: 8),
              _MoreMenuCard(
                icon: Icons.thumb_up_alt_rounded,
                title: 'Recommendation',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RecommendationScreen()),
                  );
                },
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F5F9),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xFFE7E8EE)),
                ),
                child: const Center(
                  child: Text(
                    'SIGN OUT',
                    style: TextStyle(
                      color: Color(0xFF8A2A37),
                      fontSize: 12,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Center(
                child: Text(
                  'MAPPING V.A.D. • CRAFTED WITH INTENTION',
                  style: TextStyle(
                    color: Color(0xFFA8AAB4),
                    fontSize: 7.5,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RenewPill extends StatelessWidget {
  const _RenewPill();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFA98BFF).withOpacity(0.42),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Text(
        'RENEW',
        style: TextStyle(
          color: Colors.white,
          fontSize: 9.5,
          letterSpacing: 1,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MoreMenuCard extends StatelessWidget {
  const _MoreMenuCard({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F3F8),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFFEAEAF2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 14, color: const Color(0xFF6F39E8)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        fontSize: 8.5,
                        color: Color(0xFF8F919C),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 16, color: Color(0xFFA6A8B3)),
          ],
        ),
      ),
    );
  }
}

enum PlanTier { basic, standard, premium }

class UpgradePlanScreen extends StatefulWidget {
  const UpgradePlanScreen({super.key});

  @override
  State<UpgradePlanScreen> createState() => _UpgradePlanScreenState();
}

class _UpgradePlanScreenState extends State<UpgradePlanScreen> {
  PlanTier selectedPlan = PlanTier.premium;

  @override
  Widget build(BuildContext context) {
    final plan = _planData[selectedPlan]!;
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6FA),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 86),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.menu_rounded, color: Color(0xFF6E6F7A), size: 16),
                  Spacer(),
                  Text(
                    'MindSync',
                    style: TextStyle(
                      color: Color(0xFF6F39E8),
                      fontWeight: FontWeight.w700,
                      fontSize: 22,
                    ),
                  ),
                  Spacer(),
                  Icon(Icons.notifications, color: Color(0xFF6F39E8), size: 14),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'UNLOCK SYNERGY',
                style: TextStyle(
                  color: Color(0xFFA2A4AF),
                  letterSpacing: 1.2,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Choose your\njourney.',
                style: TextStyle(
                  height: 1.02,
                  fontSize: 50,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF14151D),
                ),
              ),
              const SizedBox(height: 12),
              _PlanTabs(
                selectedPlan: selectedPlan,
                onSelect: (plan) => setState(() => selectedPlan = plan),
              ),
              const SizedBox(height: 14),
              _PlanPriceCard(plan: plan),
              const SizedBox(height: 14),
              const Text(
                'Compare Benefits',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 29),
              ),
              const SizedBox(height: 10),
              _BenefitRow(
                title: 'Shared Calendar',
                subtitle: 'Sync with all devices',
                active: selectedPlan != PlanTier.basic,
              ),
              _BenefitRow(
                title: 'Neural Insights',
                subtitle: 'Advanced pattern matching',
                active: selectedPlan == PlanTier.premium,
              ),
              _BenefitRow(
                title: 'Offline Mode',
                subtitle: 'Available everywhere',
                active: selectedPlan != PlanTier.basic,
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                height: 125,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF31404A), Color(0xFF5B4C8E), Color(0xFF1D2C37)],
                  ),
                ),
                child: const Align(
                  alignment: Alignment.bottomLeft,
                  child: Text(
                    '"The clarity I\'ve gained through\nMindSync Premium is life-\nchanging."',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanTabs extends StatelessWidget {
  const _PlanTabs({required this.selectedPlan, required this.onSelect});
  final PlanTier selectedPlan;
  final ValueChanged<PlanTier> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          _PlanTab(
            text: 'Basic',
            active: selectedPlan == PlanTier.basic,
            onTap: () => onSelect(PlanTier.basic),
          ),
          _PlanTab(
            text: 'Standard',
            active: selectedPlan == PlanTier.standard,
            onTap: () => onSelect(PlanTier.standard),
          ),
          _PlanTab(
            text: 'Premium',
            active: selectedPlan == PlanTier.premium,
            onTap: () => onSelect(PlanTier.premium),
          ),
        ],
      ),
    );
  }
}

class _PlanTab extends StatelessWidget {
  const _PlanTab({
    required this.text,
    required this.active,
    required this.onTap,
  });
  final String text;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF6F39E8) : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11,
              color: active ? Colors.white : const Color(0xFF383944),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _PlanPriceCard extends StatelessWidget {
  const _PlanPriceCard({required this.plan});
  final _PlanData plan;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8FB),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF6F39E8), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A5F34D4),
            blurRadius: 12,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                plan.title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (plan.badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDE9FB),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    plan.badge!,
                    style: const TextStyle(
                      fontSize: 8.5,
                      color: Color(0xFF7A4FE8),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(plan.subtitle, style: const TextStyle(color: Color(0xFF747683), fontSize: 11)),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$${plan.price}',
                style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800, height: 1),
              ),
              const SizedBox(width: 3),
              const Padding(
                padding: EdgeInsets.only(bottom: 7),
                child: Text('/mo', style: TextStyle(color: Color(0xFF747683), fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...plan.features.map((f) => _PlanFeatureRow(feature: f)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: const Color(0xFF6F39E8),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              child: Text(
                plan.buttonLabel,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanFeatureRow extends StatelessWidget {
  const _PlanFeatureRow({required this.feature});
  final String feature;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: const Color(0xFFEDE9FB),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.auto_awesome, size: 10, color: Color(0xFF6F39E8)),
          ),
          const SizedBox(width: 8),
          Text(feature, style: const TextStyle(fontSize: 12.5)),
        ],
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({
    required this.title,
    required this.subtitle,
    required this.active,
  });
  final String title;
  final String subtitle;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F3F8),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                Text(subtitle, style: const TextStyle(fontSize: 8.5, color: Color(0xFF9B9DA8))),
              ],
            ),
          ),
          Icon(
            active ? Icons.check_circle : Icons.cancel,
            size: 14,
            color: active ? const Color(0xFF0E9186) : const Color(0xFFCBCDD7),
          ),
        ],
      ),
    );
  }
}

class _PlanData {
  const _PlanData({
    required this.title,
    required this.subtitle,
    required this.price,
    required this.features,
    required this.buttonLabel,
    this.badge,
  });
  final String title;
  final String subtitle;
  final int price;
  final List<String> features;
  final String buttonLabel;
  final String? badge;
}

const Map<PlanTier, _PlanData> _planData = {
  PlanTier.basic: _PlanData(
    title: 'Basic',
    subtitle: 'For daily starters',
    price: 9,
    features: [
      'Mood Tracking',
      'Daily Insights',
      'Basic Focus Tools',
      'Community Access',
    ],
    buttonLabel: 'Go Basic',
  ),
  PlanTier.standard: _PlanData(
    title: 'Standard',
    subtitle: 'For growth seekers',
    price: 19,
    features: [
      'Priority AI Response',
      'Weekly Reports',
      'Guided Sessions',
      'Family Sync (2 Users)',
    ],
    buttonLabel: 'Go Standard',
  ),
  PlanTier.premium: _PlanData(
    title: 'Premium',
    subtitle: 'For power synchronizers',
    price: 29,
    features: [
      'Priority AI Response',
      'Family Sync (6 Users)',
      'Neural Landscapes',
      '1-on-1 Monthly Coaching',
    ],
    buttonLabel: 'Go Premium',
    badge: 'MOST\nPOPULAR',
  ),
};

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6FA),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 86),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.menu_rounded, color: Color(0xFF595B67), size: 18),
                  const Spacer(),
                  const Text(
                    'MindSync',
                    style: TextStyle(
                      color: Color(0xFF6F39E8),
                      fontWeight: FontWeight.w700,
                      fontSize: 23,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ReportScreen()),
                      );
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEDE9FB),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.insights_rounded, color: Color(0xFF6F39E8), size: 13),
                          SizedBox(width: 4),
                          Text(
                            'Report',
                            style: TextStyle(
                              color: Color(0xFF6F39E8),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Good morning, Alex',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text(
                'How is your mind feeling today? I\'m here to\nlisten and help you find your focus.',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: Color(0xFF565865),
                ),
              ),
              const SizedBox(height: 16),
              const _ChatRoleLabel('ASSISTANT'),
              const SizedBox(height: 6),
              const _AssistantBubble(
                text:
                    'Hello! I noticed your sleep\ndata shows a bit of\nrestlessness last night. Would\nyou like to try a 5-minute\nbreathing exercise before we\nstart our session?',
              ),
              const SizedBox(height: 14),
              const Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'USER',
                  style: TextStyle(
                    color: Color(0xFF8A8C98),
                    letterSpacing: 1.4,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Align(
                alignment: Alignment.centerRight,
                child: _UserBubble(
                  text:
                      'I\'m feeling quite overwhelmed\nwith work. I have a big\npresentation in two hours and\nI can\'t seem to quiet my racing\nthoughts.',
                ),
              ),
              const SizedBox(height: 14),
              const _ChatRoleLabel('ASSISTANT'),
              const SizedBox(height: 6),
              const _AssistantBubble(
                text:
                    'It\'s completely natural to feel\nthat way before a\npresentation. Let\'s focus on\ngrounding you. Shall we try\nthe \'Box Breathing\' technique\nor would you prefer to talk\nthrough your main stressors\nfirst?',
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const [
                  _QuickReplyChip(
                    text: 'I feel stressed',
                    bg: Color(0xFFC6F2ED),
                    fg: Color(0xFF126F69),
                  ),
                  _QuickReplyChip(
                    text: 'How can I focus?',
                    bg: Color(0xFFEDE9FB),
                    fg: Color(0xFF6F39E8),
                  ),
                  _QuickReplyChip(
                    text: 'Morning routine',
                    bg: Color(0xFFEAEFFB),
                    fg: Color(0xFF385A87),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatRoleLabel extends StatelessWidget {
  const _ChatRoleLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF8A8C98),
        letterSpacing: 1.6,
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F9FC),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 128,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF6F39E8), Color(0xFF0E9186), Color(0xFF2E6FD2)],
              ),
              borderRadius: BorderRadius.all(Radius.circular(2)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 11.5, height: 1.5, color: Color(0xFF20222B)),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 214),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6F39E8), Color(0xFF7A4FE8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11.5, height: 1.5, color: Colors.white),
      ),
    );
  }
}

class _QuickReplyChip extends StatelessWidget {
  const _QuickReplyChip({
    required this.text,
    required this.bg,
    required this.fg,
  });
  final String text;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(18)),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class CommunityScreen extends StatelessWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6FA),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  CircleAvatar(
                    radius: 11,
                    backgroundColor: Color(0xFF252525),
                    child: Icon(Icons.person, size: 11, color: Colors.white),
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Community',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2B2E3D),
                      fontSize: 16,
                    ),
                  ),
                  Spacer(),
                  Icon(Icons.notifications, size: 14, color: Color(0xFF6F39E8)),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Find your\ncalming breath.',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, height: 1.1),
              ),
              const SizedBox(height: 4),
              const Text(
                'A shared space for stories,\nstrategies and moments of quiet\nresilience.',
                style: TextStyle(fontSize: 10.5, color: Color(0xFF676977), height: 1.35),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.chat_bubble_outline, size: 12, color: Color(0xFF7E4AE7)),
                        SizedBox(width: 8),
                        Text(
                          'Share a thought or a\nstress relief strategy',
                          style: TextStyle(fontSize: 10.5, color: Color(0xFF777987)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.image, size: 12, color: Color(0xFF676977)),
                        const SizedBox(width: 8),
                        const Icon(Icons.tag, size: 12, color: Color(0xFF676977)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6F39E8),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Text(
                            'Post Thought',
                            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              const Row(
                children: [
                  _CommunityTag(text: 'All Stories', active: true),
                  SizedBox(width: 6),
                  _CommunityTag(text: '#Stress'),
                  SizedBox(width: 6),
                  _CommunityTag(text: '#SelfCare'),
                ],
              ),
              const SizedBox(height: 10),
              const _CommunityPostCard(
                author: 'Anonymous Seeker',
                time: '2 HOURS AGO',
                title: 'Dealing with exam stress\nthrough micro-meditation',
                body:
                    'I\'ve found that doing 2-minute "reset\nbreaths" between study sessions\nreally helps keep the panic at bay. I\njust focus on the sensation of air on\nmy upper lip, it sounds simple, but it\nworks wonders for my focus levels',
                tags: '#STRESS      #STUDYTIPS',
                likes: '126',
                comments: '18',
                accent: Color(0xFFC6F2ED),
              ),
              const SizedBox(height: 10),
              const _CommunityPostCard(
                author: 'Marcus L.',
                time: '3 HOURS AGO',
                title: 'The power of evening digital\ndetox',
                body:
                    'I stopped using my phone at 8 PM for\n1 week. My sleep quality shot up, and\nmy morning anxiety almost\ndisappeared. Replacing the scroll with\na physical book is the best strategy\nI\'ve tried this year.',
                tags: '#SELFCARE      #WELLBEING',
                likes: '2.4k',
                comments: '89',
                accent: Color(0xFFFCE3E2),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        backgroundColor: const Color(0xFF6F39E8),
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _CommunityTag extends StatelessWidget {
  const _CommunityTag({required this.text, this.active = false});
  final String text;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active ? const Color(0xFF6F39E8) : const Color(0xFFEDEEF4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: active ? Colors.white : const Color(0xFF6D6F7A),
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _CommunityPostCard extends StatelessWidget {
  const _CommunityPostCard({
    required this.author,
    required this.time,
    required this.title,
    required this.body,
    required this.tags,
    required this.likes,
    required this.comments,
    required this.accent,
  });
  final String author;
  final String time;
  final String title;
  final String body;
  final String tags;
  final String likes;
  final String comments;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(radius: 10, backgroundColor: accent, child: const Icon(Icons.person, size: 10)),
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(author, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700)),
                  Text(time, style: const TextStyle(fontSize: 8, color: Color(0xFFA1A3AE))),
                ],
              ),
              const Spacer(),
              const Icon(Icons.more_horiz, size: 14, color: Color(0xFF8E909C)),
            ],
          ),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.2)),
          const SizedBox(height: 6),
          Text(body, style: const TextStyle(fontSize: 10.5, color: Color(0xFF5F616F), height: 1.35)),
          const SizedBox(height: 7),
          Text(tags, style: const TextStyle(fontSize: 8.5, color: Color(0xFF7A4FE8), fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.favorite, size: 12, color: Color(0xFF161720)),
              const SizedBox(width: 4),
              Text(likes, style: const TextStyle(fontSize: 9.5)),
              const SizedBox(width: 12),
              const Icon(Icons.chat_bubble, size: 12, color: Color(0xFF161720)),
              const SizedBox(width: 4),
              Text(comments, style: const TextStyle(fontSize: 9.5)),
              const Spacer(),
              const Icon(Icons.share, size: 12, color: Color(0xFF41434F)),
            ],
          ),
        ],
      ),
    );
  }
}

class EmergencyScreen extends StatelessWidget {
  const EmergencyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6FA),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 17),
                  ),
                  const Text(
                    'Emergency',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFECEC),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Color(0xFFD24545)),
                        SizedBox(width: 8),
                        Text(
                          'Need immediate help?',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF922B2B)),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      'If you are in danger or having a severe crisis, contact emergency services immediately.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF7D4242), height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD24545),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                  ),
                  icon: const Icon(Icons.call),
                  label: const Text('Call Emergency Services', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Trusted Contacts', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const _EmergencyContactCard(name: 'Elena Vance', relation: 'Guardian', phone: '+92 300 1234567'),
              const _EmergencyContactCard(name: 'Marcus L.', relation: 'Friend', phone: '+92 301 9876543'),
              const _EmergencyContactCard(name: 'Dr. Sana', relation: 'Therapist', phone: '+92 322 4567890'),
              const Spacer(),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                child: const Text(
                  'You are not alone. Breathe in for 4 seconds, hold for 4, and exhale for 6. Repeat 5 times.',
                  style: TextStyle(fontSize: 11.5, color: Color(0xFF525563), height: 1.4),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmergencyContactCard extends StatelessWidget {
  const _EmergencyContactCard({
    required this.name,
    required this.relation,
    required this.phone,
  });
  final String name;
  final String relation;
  final String phone;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 16,
            backgroundColor: Color(0xFFEDE9FB),
            child: Icon(Icons.person, size: 15, color: Color(0xFF6F39E8)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('$relation • $phone', style: const TextStyle(fontSize: 10, color: Color(0xFF7E8090))),
              ],
            ),
          ),
          IconButton(onPressed: () {}, icon: const Icon(Icons.call, color: Color(0xFF0E9186))),
        ],
      ),
    );
  }
}

class ReportScreen extends StatelessWidget {
  const ReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6FA),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
                  ),
                  const Text(
                    'MindSync Report',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Weekly Mental Summary',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              const Text(
                'Focused on your recent mood and focus patterns.',
                style: TextStyle(fontSize: 11, color: Color(0xFF6A6C79)),
              ),
              const SizedBox(height: 12),
              const _ReportMetricRow(),
              const SizedBox(height: 12),
              _ReportSection(
                title: 'Stress Trend',
                value: 'Moderate',
                subtitle: 'Slight increase before deadlines',
                color: const Color(0xFF6F39E8),
              ),
              _ReportSection(
                title: 'Sleep Quality',
                value: '7h 12m avg',
                subtitle: 'Improved consistency after 11PM screen limit',
                color: const Color(0xFF0E9186),
              ),
              _ReportSection(
                title: 'Focus Sessions',
                value: '14 completed',
                subtitle: 'Best performance between 9AM - 11AM',
                color: const Color(0xFF2E6FD2),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Recommended Next Step', style: TextStyle(fontWeight: FontWeight.w700)),
                    SizedBox(height: 6),
                    Text(
                      'Use a 5-minute breathing reset before major meetings and keep evening screen time below 1 hour.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF595B69), height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportMetricRow extends StatelessWidget {
  const _ReportMetricRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: _ReportMetricCard(title: 'Mood', value: '72')),
        SizedBox(width: 8),
        Expanded(child: _ReportMetricCard(title: 'Focus', value: '81')),
        SizedBox(width: 8),
        Expanded(child: _ReportMetricCard(title: 'Recovery', value: '68')),
      ],
    );
  }
}

class _ReportMetricCard extends StatelessWidget {
  const _ReportMetricCard({required this.title, required this.value});
  final String title;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          Text(title, style: const TextStyle(fontSize: 10, color: Color(0xFF7E8090))),
        ],
      ),
    );
  }
}

class _ReportSection extends StatelessWidget {
  const _ReportSection({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
  });
  final String title;
  final String value;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 48,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                Text(subtitle, style: const TextStyle(fontSize: 9.5, color: Color(0xFF7A7D8B))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class RecommendationScreen extends StatelessWidget {
  const RecommendationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6FA),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  CircleAvatar(radius: 10, child: Icon(Icons.person, size: 11)),
                  SizedBox(width: 6),
                  Text('MindSync', style: TextStyle(color: Color(0xFF5A5FCD), fontWeight: FontWeight.w700)),
                  Spacer(),
                  Icon(Icons.settings, size: 14),
                ],
              ),
              const SizedBox(height: 10),
              const Text('Sanctuary\nRecommendations', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.05)),
              const Text('Curated for your wellbeing', style: TextStyle(fontSize: 11, color: Color(0xFF747683))),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(colors: [Color(0xFF6F39E8), Color(0xFF7B8BEF)]),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TIP OF THE DAY', style: TextStyle(color: Color(0xFFDBD0FF), fontSize: 8.5, fontWeight: FontWeight.w700)),
                    SizedBox(height: 4),
                    Text('The 20-20-20 Rule', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
                    SizedBox(height: 4),
                    Text('Every 20 minutes, look at\nsomething 20 feet away for\n20 seconds to significantly\nreduce digital eye strain.', style: TextStyle(color: Colors.white, fontSize: 10.5, height: 1.3)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text('Daily Rhythm', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 8),
              const _RecoSmallTile(title: 'Morning Walk', subtitle: '10-min target walk to boost mood'),
              const _RecoSmallTile(title: 'Phone-Free Hour', subtitle: 'Break from digital noise for clarity'),
              const _RecoSmallTile(title: 'Connect with Loved Ones', subtitle: 'Strengthen daily bonds'),
              const SizedBox(height: 10),
              const Text('Curated Content', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 8),
              const _RecoImageTile(title: 'Guided Meditation for Focus'),
              const SizedBox(height: 8),
              const _RecoImageTile(title: 'The Art of Deep Sleep'),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecoSmallTile extends StatelessWidget {
  const _RecoSmallTile({required this.title, required this.subtitle});
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          const CircleAvatar(radius: 12, backgroundColor: Color(0xFFDDF7F4), child: Icon(Icons.self_improvement, size: 12, color: Color(0xFF0E9186))),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
              Text(subtitle, style: const TextStyle(fontSize: 9.5, color: Color(0xFF7F8190))),
            ]),
          ),
          const Icon(Icons.chevron_right, size: 14, color: Color(0xFF8D8F9B)),
        ],
      ),
    );
  }
}

class _RecoImageTile extends StatelessWidget {
  const _RecoImageTile({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 88,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(colors: [Color(0xFF273842), Color(0xFF6A5D93)]),
      ),
      child: Align(
        alignment: Alignment.bottomLeft,
        child: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
      ),
    );
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6FA),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 15, color: Color(0xFF6F39E8)),
                  ),
                  const Spacer(),
                  const Text('Edit Profile', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  const Spacer(),
                  TextButton(onPressed: () {}, child: const Text('Save', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                ],
              ),
              const SizedBox(height: 8),
              const Center(
                child: CircleAvatar(
                  radius: 34,
                  backgroundColor: Color(0xFF233142),
                  child: Icon(Icons.person, color: Colors.white, size: 36),
                ),
              ),
              const SizedBox(height: 8),
              const Center(child: Text('Alex Rivers', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 22))),
              const Center(child: Text('MindSync Premium Member', style: TextStyle(color: Color(0xFF8A8C98), fontSize: 10.5))),
              const SizedBox(height: 14),
              const Text('PERSONAL INFORMATION', style: TextStyle(color: Color(0xFF8B8D98), letterSpacing: 1.5, fontSize: 9, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const _ProfileCard(),
              const SizedBox(height: 10),
              const Text('SECURITY', style: TextStyle(color: Color(0xFF8B8D98), letterSpacing: 1.5, fontSize: 9, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const _SecurityCard(),
              const SizedBox(height: 10),
              const Text('AUTHENTICATION', style: TextStyle(color: Color(0xFF8B8D98), letterSpacing: 1.5, fontSize: 9, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const _AuthCard(),
              const SizedBox(height: 10),
              const Text('ACCOUNT SETTINGS', style: TextStyle(color: Color(0xFF8B8D98), letterSpacing: 1.5, fontSize: 9, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const _AccountCard(),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6F39E8),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                  child: const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: const Column(
        children: [
          _Field(label: 'Full Name', value: 'Alex Rivers'),
          _Field(label: 'Username', value: 'arivers_sync'),
          _Field(label: 'Email Address', value: 'alex.rivers@mindsync.io'),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(color: const Color(0xFFF1F2F6), borderRadius: BorderRadius.circular(8)),
          child: Text(value, style: const TextStyle(fontSize: 11)),
        ),
      ]),
    );
  }
}

class _SecurityCard extends StatelessWidget {
  const _SecurityCard();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Column(
        children: [
          const Row(children: [
            CircleAvatar(radius: 12, backgroundColor: Color(0xFFE6F0FF), child: Icon(Icons.lock, size: 12, color: Color(0xFF2E6FD2))),
            SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Password', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
              Text('Last changed 3 months ago', style: TextStyle(fontSize: 9, color: Color(0xFF8D909D))),
            ])
          ]),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: () {}, child: const Text('Change Password')),
        ],
      ),
    );
  }
}

class _AuthCard extends StatelessWidget {
  const _AuthCard();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Column(children: [
        const Row(children: [
          CircleAvatar(radius: 12, backgroundColor: Color(0xFFC6F2ED), child: Icon(Icons.fingerprint, size: 12, color: Color(0xFF0E9186))),
          SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Face Scan', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
            Text('Face Registered', style: TextStyle(fontSize: 9, color: Color(0xFF8D909D))),
          ])
        ]),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 40,
          child: ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6F39E8),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: const Text('Re-scan Face'),
          ),
        ),
      ]),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: const Column(
        children: [
          _Field(label: 'Phone Number', value: '+1 (555) 012-3456'),
          _Field(label: 'Date of Birth', value: 'March 12, 1994'),
        ],
      ),
    );
  }
}

enum AnalyticsRange { week, day, month }

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  AnalyticsRange selectedRange = AnalyticsRange.week;

  final Map<AnalyticsRange, _AnalyticsData> dataByRange = {
    AnalyticsRange.day: const _AnalyticsData(
      sleep: '7h 45m',
      sleepTrend: '+12% vs last week',
      screenTime: '4h 12m',
      categories: {'Social': 0.60, 'Games': 0.25, 'Study': 0.15},
      mood: [0, 2, 1, 2, 0, 1, 0],
      focusSessions: [
        _FocusSession('Deep Work', 'Completed · 45 mins'),
        _FocusSession('Meditation', 'Interrupted · 12 mins'),
      ],
    ),
    AnalyticsRange.week: const _AnalyticsData(
      sleep: '7h 32m',
      sleepTrend: '+8% vs last week',
      screenTime: '27h 44m',
      categories: {'Social': 0.53, 'Games': 0.19, 'Study': 0.28},
      mood: [1, 2, 0, 2, 2, 1, 2],
      focusSessions: [
        _FocusSession('Weekly Reflection', 'Completed · 30 mins'),
        _FocusSession('Deep Work', 'Completed · 3h 10 mins'),
      ],
    ),
    AnalyticsRange.month: const _AnalyticsData(
      sleep: '7h 08m',
      sleepTrend: '+4% vs previous month',
      screenTime: '116h 20m',
      categories: {'Social': 0.49, 'Games': 0.18, 'Study': 0.33},
      mood: [1, 1, 2, 1, 2, 2, 1],
      focusSessions: [
        _FocusSession('Mindful Breathing', 'Completed · 6 sessions'),
        _FocusSession('Deep Work', 'Completed · 12 sessions'),
      ],
    ),
  };

  @override
  Widget build(BuildContext context) {
    final data = dataByRange[selectedRange]!;
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6FA),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.menu_rounded, color: Color(0xFF3B3B46)),
                  Spacer(),
                  Text(
                    'MindSync',
                    style: TextStyle(
                      color: Color(0xFF6F39E8),
                      fontWeight: FontWeight.w700,
                      fontSize: 31,
                    ),
                  ),
                  Spacer(),
                  Icon(Icons.notifications, color: Color(0xFF6F39E8)),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                'INSIGHTS & TRENDS',
                style: TextStyle(
                  color: Color(0xFF9A97AD),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Focus &\nBalance',
                style: TextStyle(
                  height: 1.1,
                  fontSize: 46,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF14151B),
                ),
              ),
              const SizedBox(height: 16),
              _RangeSelector(
                selectedRange: selectedRange,
                onChanged: (value) {
                  setState(() => selectedRange = value);
                },
              ),
              const SizedBox(height: 16),
              _StatCard(
                title: 'SLEEP QUALITY',
                value: data.sleep,
                subtitle: data.sleepTrend,
                trailing: Container(
                  width: 58,
                  height: 58,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF72E4D8),
                  ),
                  child: const Icon(Icons.nightlight_round, color: Colors.black87),
                ),
              ),
              const SizedBox(height: 12),
              _ScreenTimeCard(value: data.screenTime),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _CategoriesCard(categories: data.categories),
                  ),
                  const SizedBox(width: 12),
                  const _StressCard(),
                ],
              ),
              const SizedBox(height: 12),
              _MoodCard(moodValues: data.mood),
              const SizedBox(height: 14),
              const Text(
                'Focus Session History',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 31),
              ),
              const SizedBox(height: 8),
              ...data.focusSessions.map((session) => _FocusSessionTile(session)),
            ],
          ),
        ),
      ),
    );
  }
}

class _InputBox extends StatelessWidget {
  const _InputBox({required this.hint, this.obscure = false});

  final String hint;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    return TextField(
      obscureText: obscure,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFF1F2F6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(26),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.label,
    required this.background,
    required this.textColor,
  });

  final String label;
  final Color background;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE0E0E7)),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _BottomItem extends StatelessWidget {
  const _BottomItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    if (highlighted && isActive) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF6F39E8),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      );
    }
    final color = isActive ? const Color(0xFF6F39E8) : const Color(0xFFA8A8B8);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 56,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _RangeSelector extends StatelessWidget {
  const _RangeSelector({required this.selectedRange, required this.onChanged});

  final AnalyticsRange selectedRange;
  final ValueChanged<AnalyticsRange> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F5),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          _RangeChip(
            label: 'Week',
            active: selectedRange == AnalyticsRange.week,
            onTap: () => onChanged(AnalyticsRange.week),
          ),
          _RangeChip(
            label: 'Day',
            active: selectedRange == AnalyticsRange.day,
            onTap: () => onChanged(AnalyticsRange.day),
          ),
          _RangeChip(
            label: 'Month',
            active: selectedRange == AnalyticsRange.month,
            onTap: () => onChanged(AnalyticsRange.month),
          ),
        ],
      ),
    );
  }
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF6F39E8) : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            boxShadow:
                active
                    ? const [
                      BoxShadow(
                        color: Color(0x445F34D4),
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ]
                    : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : const Color(0xFF3A3B46),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.trailing,
  });

  final String title;
  final String value;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF9A97AD),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  value,
                  style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF1C1E25),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

class _ScreenTimeCard extends StatelessWidget {
  const _ScreenTimeCard({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'AVG. SCREEN TIME',
            style: TextStyle(
              color: Color(0xFF9A97AD),
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 62,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (index) {
                final heights = [30.0, 46.0, 42.0, 62.0, 28.0, 40.0, 43.0];
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Container(
                      height: heights[index],
                      decoration: BoxDecoration(
                        color:
                            index == 3
                                ? const Color(0xFF6F39E8)
                                : const Color(0xFFE4E5EC),
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoriesCard extends StatelessWidget {
  const _CategoriesCard({required this.categories});

  final Map<String, double> categories;

  @override
  Widget build(BuildContext context) {
    final social = ((categories['Social'] ?? 0) * 100).round();
    final games = ((categories['Games'] ?? 0) * 100).round();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CATEGORIES',
            style: TextStyle(
              color: Color(0xFF9A97AD),
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 12),
          const Center(
            child: SizedBox(width: 92, height: 92, child: _CategoryRing()),
          ),
          const SizedBox(height: 10),
          Text(
            '• Social ($social%)',
            style: const TextStyle(fontSize: 12, color: Color(0xFF444554)),
          ),
          const SizedBox(height: 2),
          Text(
            '• Games ($games%)',
            style: const TextStyle(fontSize: 12, color: Color(0xFF444554)),
          ),
        ],
      ),
    );
  }
}

class _CategoryRing extends StatelessWidget {
  const _CategoryRing();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RingPainter(),
      child: const Center(
        child: Text(
          'Daily',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 5;
    final bg =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10
          ..color = const Color(0xFFE9E9F1);
    canvas.drawCircle(center, radius, bg);
    final a =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 10
          ..color = const Color(0xFF6F39E8);
    final b =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 10
          ..color = const Color(0xFF58DDD2);
    const start = -1.57;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      start,
      3.6,
      false,
      a,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      start + 3.7,
      1.3,
      false,
      b,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _StressCard extends StatelessWidget {
  const _StressCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 98,
      height: 178,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0B66D8),
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.spa_rounded, color: Color(0xFF9BD6FF), size: 14),
          Spacer(),
          Text(
            'STRESS',
            style: TextStyle(
              color: Color(0xFFB7DBFF),
              fontWeight: FontWeight.w700,
              fontSize: 10,
            ),
          ),
          Text(
            'Stable',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 30),
          ),
          SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _MoodCard extends StatelessWidget {
  const _MoodCard({required this.moodValues});
  final List<int> moodValues;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text(
                'MOOD FREQUENCY',
                style: TextStyle(
                  color: Color(0xFF9A97AD),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  fontSize: 11,
                ),
              ),
              Spacer(),
              Text(
                'DETAILS',
                style: TextStyle(
                  color: Color(0xFF8A7ACC),
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (index) {
              final mood = index < moodValues.length ? moodValues[index] : 0;
              final color =
                  mood == 2
                      ? const Color(0xFF6F39E8)
                      : mood == 1
                      ? const Color(0xFFB0A2E6)
                      : const Color(0xFFC6F2ED);
              return Container(
                width: 29,
                height: 29,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Icon(
                  Icons.sentiment_satisfied_rounded,
                  size: 16,
                  color: mood == 0 ? const Color(0xFF4CA49B) : Colors.white,
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _FocusSessionTile extends StatelessWidget {
  const _FocusSessionTile(this.session);
  final _FocusSession session;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              color: Color(0xFFF0EBFF),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.alarm, size: 16, color: Color(0xFF6F39E8)),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                session.title,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
              ),
              Text(
                session.subtitle,
                style: const TextStyle(color: Color(0xFF838391), fontSize: 13),
              ),
            ],
          ),
          const Spacer(),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFFBCBCC8)),
        ],
      ),
    );
  }
}

class _AnalyticsData {
  const _AnalyticsData({
    required this.sleep,
    required this.sleepTrend,
    required this.screenTime,
    required this.categories,
    required this.mood,
    required this.focusSessions,
  });

  final String sleep;
  final String sleepTrend;
  final String screenTime;
  final Map<String, double> categories;
  final List<int> mood;
  final List<_FocusSession> focusSessions;
}

class _FocusSession {
  const _FocusSession(this.title, this.subtitle);
  final String title;
  final String subtitle;
}
