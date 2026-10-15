from django.test import SimpleTestCase
from django.urls import reverse


class ApiHealthTests(SimpleTestCase):
    def test_health_endpoint_returns_ok(self):
        response = self.client.get(reverse('api_health'))
        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertTrue(payload.get('ok'))
        self.assertEqual(payload.get('service'), 'MindSync API')
