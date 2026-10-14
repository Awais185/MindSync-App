import 'package:flutter_stripe/flutter_stripe.dart';

/// Mobile-only Stripe publishable key (set before PaymentSheet).
Future<void> initializeStripePublishableKey() async {
  Stripe.publishableKey = const String.fromEnvironment(
    'STRIPE_PUBLISHABLE_KEY',
    defaultValue: 'pk_test_placeholder',
  );
}

bool get isStripePaymentSupported => true;
