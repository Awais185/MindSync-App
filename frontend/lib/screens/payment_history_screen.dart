import 'package:flutter/material.dart';

import '../services/payment_service.dart';

class PaymentHistoryScreen extends StatefulWidget {
  const PaymentHistoryScreen({super.key});

  @override
  State<PaymentHistoryScreen> createState() => _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends State<PaymentHistoryScreen> {
  late Future<List<Map<String, dynamic>>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _historyFuture = PaymentService.instance.fetchPaymentHistory();
  }

  String _formatAmount(dynamic amount, String currency) {
    final value = double.tryParse(amount.toString()) ?? 0;
    final sym = currency.toLowerCase() == 'usd' ? '\$' : '';
    return '$sym${value.toStringAsFixed(2)}';
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'succeeded':
        return const Color(0xFF22A45D);
      case 'failed':
        return const Color(0xFFD32F2F);
      default:
        return const Color(0xFF8A8C98);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: const Color(0xFF1C1C1E),
        title: const Text('Payment History', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _historyFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snap.data ?? const [];
          if (rows.isEmpty) {
            return const Center(child: Text('No payments yet.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final row = rows[i];
              final plan = (row['plan_name'] ?? '').toString();
              final status = (row['status'] ?? '').toString();
              final paidAt = DateTime.tryParse((row['paid_at'] ?? '').toString());
              final dateStr = paidAt != null
                  ? '${paidAt.year}-${paidAt.month.toString().padLeft(2, '0')}-${paidAt.day.toString().padLeft(2, '0')}'
                  : '';
              return Card(
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: ListTile(
                  title: Text(plan.isEmpty ? 'Subscription' : plan.toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(dateStr),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _formatAmount(row['amount'], (row['currency'] ?? 'usd').toString()),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _statusColor(status).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _statusColor(status),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
