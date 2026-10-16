import '../models/analytics_dashboard_payload.dart';
import 'api_client.dart';

/// Single API for the Analytics tab (`GET /api/auth/analytics/dashboard/`).
class AnalyticsDashboardService {
  AnalyticsDashboardService._();
  static final AnalyticsDashboardService instance = AnalyticsDashboardService._();

  Future<AnalyticsDashboardPayload> fetch(String period) async {
    final normalized = switch (period) {
      'day' => 'day',
      'month' => 'month',
      _ => 'week',
    };
    final json = await ApiClient.instance.getJson(
      '/api/auth/analytics/dashboard/?period=$normalized',
    );
    if (json == null) return AnalyticsDashboardPayload.empty;
    return AnalyticsDashboardPayload.fromJson(json);
  }
}
