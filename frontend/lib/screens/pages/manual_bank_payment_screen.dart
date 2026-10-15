import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/subscription_service.dart';

/// Bank transfer payment — gallery proof only (no camera).
class ManualBankPaymentScreen extends StatefulWidget {
  const ManualBankPaymentScreen({
    super.key,
    required this.plan,
  });

  final SubscriptionPlanModel plan;

  @override
  State<ManualBankPaymentScreen> createState() => _ManualBankPaymentScreenState();
}

class _ManualBankPaymentScreenState extends State<ManualBankPaymentScreen> {
  final _refController = TextEditingController();
  final _picker = ImagePicker();
  Map<String, dynamic> _bankDetails = const {};
  XFile? _proof;
  int? _paymentId;
  bool _loading = false;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _loadBankDetails();
  }

  @override
  void dispose() {
    _refController.dispose();
    super.dispose();
  }

  Future<void> _loadBankDetails() async {
    final details = await SubscriptionService.instance.getBankDetails();
    if (!mounted) return;
    setState(() => _bankDetails = details);
  }

  Future<void> _pickProofFromGallery() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (file == null || !mounted) return;
    setState(() => _proof = file);
  }

  Future<void> _submit() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final service = SubscriptionService.instance;
      var paymentId = _paymentId;
      if (paymentId == null) {
        final created = await service.createManualPayment(
          planId: widget.plan.id,
          transactionReference: _refController.text.trim(),
        );
        if (created == null) {
          _toast('Could not create payment request.');
          return;
        }
        paymentId = created.paymentId;
        _paymentId = paymentId;
      }

      final ok = await service.uploadPaymentProof(
        paymentId: paymentId,
        transactionReference: _refController.text.trim(),
        proofFile: _proof,
      );
      if (!ok) {
        _toast('Could not upload payment proof.');
        return;
      }
      setState(() => _submitted = true);
      await service.refreshCurrentSubscription();
      _toast('Payment submitted. Awaiting admin approval.');
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text('Proceed to Payment'),
        backgroundColor: const Color(0xFFF5F6FA),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Text(
            '${plan.name} — \$${plan.priceUsd.toStringAsFixed(0)}/month',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF14151D),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Transfer the amount below, then submit your reference and screenshot.',
            style: TextStyle(fontSize: 13, color: Color(0xFF6E7381)),
          ),
          const SizedBox(height: 20),
          _BankCard(details: _bankDetails),
          const SizedBox(height: 20),
          TextField(
            controller: _refController,
            decoration: InputDecoration(
              labelText: 'Transaction reference',
              hintText: 'Bank receipt / transfer ID',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _loading ? null : _pickProofFromGallery,
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(
              _proof == null
                  ? 'Upload payment screenshot (gallery)'
                  : 'Screenshot: ${_proof!.name}',
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _loading || _submitted ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6F39E8),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Submit payment proof',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BankCard extends StatelessWidget {
  const _BankCard({required this.details});

  final Map<String, dynamic> details;

  @override
  Widget build(BuildContext context) {
    String line(String key, String label) {
      final v = (details[key] ?? '').toString().trim();
      if (v.isEmpty) return '';
      return '$label: $v';
    }

    final lines = [
      line('bank_name', 'Bank'),
      line('account_title', 'Account name'),
      line('account_number', 'Account number'),
      line('iban', 'IBAN'),
      line('swift', 'SWIFT'),
      (details['instructions'] ?? '').toString(),
    ].where((e) => e.isNotEmpty).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8EAF3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Bank details',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 10),
          ...lines.map(
            (t) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(t, style: const TextStyle(fontSize: 13, height: 1.35)),
            ),
          ),
        ],
      ),
    );
  }
}
