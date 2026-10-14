import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import '../models/plan_model.dart';
import '../services/payment_service.dart';
import '../services/subscription_service.dart';

class PaymentSheetScreen extends StatefulWidget {
  const PaymentSheetScreen({required this.plan, super.key});

  final PlanModel plan;

  @override
  State<PaymentSheetScreen> createState() => _PaymentSheetScreenState();
}

class _PaymentSheetScreenState extends State<PaymentSheetScreen> {
  final _paymentService = PaymentService.instance;
  bool _loading = true;
  bool _paying = false;
  String? _error;
  String? _clientSecret;
  String? _paymentIntentId;

  @override
  void initState() {
    super.initState();
    _preparePaymentSheet();
  }

  Future<void> _preparePaymentSheet() async {
    if (kIsWeb) {
      setState(() {
        _loading = false;
        _error = 'Card checkout is available in the Android/iOS app.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _paymentService.createPaymentIntent(widget.plan.id);
      if (result == null || result.clientSecret.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'Could not start payment. Check login and Stripe keys.';
        });
        return;
      }
      final publishableKey = result.publishableKey.isNotEmpty
          ? result.publishableKey
          : Stripe.publishableKey;
      if (publishableKey.isNotEmpty) {
        Stripe.publishableKey = publishableKey;
      }
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: result.clientSecret,
          merchantDisplayName: 'MindSync',
          style: ThemeMode.system,
        ),
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _clientSecret = result.clientSecret;
        _paymentIntentId = result.paymentIntentId;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _pay() async {
    if (kIsWeb) return;
    if (_clientSecret == null || _paymentIntentId == null) return;
    setState(() => _paying = true);
    try {
      await Stripe.instance.presentPaymentSheet();
      final sub = await _paymentService.confirmSubscription(
        paymentIntentId: _paymentIntentId!,
        planId: widget.plan.id,
      );
      if (!mounted) return;
      if (sub == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment completed but confirmation failed. Contact support.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      await SubscriptionService.instance.refreshCurrentSubscription();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Subscription active'),
          content: Text(
            '${widget.plan.displayName} is active until '
            '${sub.expiresAt != null ? _formatDate(sub.expiresAt!) : 'renewal'}.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on StripeException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.error.localizedMessage ?? 'Payment cancelled'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payment failed: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: const Color(0xFF1C1C1E),
        title: const Text('Checkout', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                plan.displayName,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                '${plan.priceLabel} / month',
                style: const TextStyle(fontSize: 16, color: Color(0xFF6F39E8), fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 20),
              const Text(
                'Includes',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: plan.features
                      .map(
                        (f) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle, size: 18, color: Color(0xFF6F39E8)),
                              const SizedBox(width: 8),
                              Expanded(child: Text(f, style: const TextStyle(fontSize: 13))),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading || _paying || _clientSecret == null ? null : _pay,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6F39E8),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  child: _loading || _paying
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Pay', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
