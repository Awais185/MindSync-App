"""Manual payment + subscription alias APIs."""

from __future__ import annotations

from rest_framework import parsers, permissions, response, status
from rest_framework.views import APIView

from .manual_payment_service import ManualPaymentService, bank_details_payload
from .models import Payment, SubscriptionPlan
from .serializers import (
    CreateManualPaymentSerializer,
    PaymentSerializer,
    UploadPaymentProofSerializer,
)
from .services import SubscriptionService
from .views import CurrentSubscriptionAPIView, FREE_PLAN_PAYLOAD
from .serializers import SubscriptionPlanSerializer, UserSubscriptionSerializer


class BankDetailsAPIView(APIView):
    permission_classes = (permissions.IsAuthenticated,)

    def get(self, request):
        return response.Response({'bank_details': bank_details_payload()})


class CreateManualPaymentAPIView(APIView):
    """POST /api/payments/create/"""

    permission_classes = (permissions.IsAuthenticated,)

    def post(self, request):
        serializer = CreateManualPaymentSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        plan = SubscriptionPlan.objects.filter(
            id=data['plan_id'],
            is_active=True,
        ).first()
        if not plan or plan.code == 'free':
            return response.Response(
                {'message': 'Selected plan is not available.'},
                status=status.HTTP_404_NOT_FOUND,
            )

        current = SubscriptionService.get_active_subscription(request.user)
        if current and current.plan_id == plan.id:
            return response.Response(
                {'message': 'You are already subscribed to this plan.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        payment = ManualPaymentService.create_payment_request(
            user=request.user,
            plan=plan,
            payment_method=data.get('payment_method') or 'bank_transfer',
            transaction_reference=data.get('transaction_reference') or '',
        )
        return response.Response(
            {
                'message': 'Payment request created. Upload proof to complete submission.',
                'payment': PaymentSerializer(payment, context={'request': request}).data,
                'subscription_id': payment.subscription_id,
                'bank_details': bank_details_payload(),
            },
            status=status.HTTP_201_CREATED,
        )


class UploadPaymentProofAPIView(APIView):
    """POST /api/payments/upload-proof/"""

    permission_classes = (permissions.IsAuthenticated,)
    parser_classes = (parsers.MultiPartParser, parsers.FormParser)

    def post(self, request):
        serializer = UploadPaymentProofSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        payment = Payment.objects.filter(
            id=data['payment_id'],
            user=request.user,
        ).select_related('plan', 'subscription').first()
        if not payment:
            return response.Response(
                {'message': 'Payment not found.'},
                status=status.HTTP_404_NOT_FOUND,
            )
        if payment.status != Payment.STATUS_PENDING:
            return response.Response(
                {'message': f'Payment is already {payment.status}.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        screenshot = data.get('screenshot_proof')
        if not screenshot and not payment.screenshot_proof:
            return response.Response(
                {'message': 'screenshot_proof image is required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        payment = ManualPaymentService.attach_proof(
            payment=payment,
            screenshot=screenshot,
            transaction_reference=data.get('transaction_reference') or '',
        )
        return response.Response(
            {
                'message': 'Payment proof submitted. Awaiting admin approval.',
                'payment': PaymentSerializer(payment, context={'request': request}).data,
            }
        )


class CurrentSubscriptionAliasAPIView(CurrentSubscriptionAPIView):
    """GET /api/subscription/current/ — alias for existing current-subscription."""

    def get(self, request):
        resp = super().get(request)
        if resp.status_code != 200:
            return resp
        data = dict(resp.data)
        sub = SubscriptionService.get_active_subscription(request.user)
        data['is_active'] = bool(sub and sub.is_active)
        if sub:
            data['subscription'] = UserSubscriptionSerializer(sub).data
            data['plan'] = SubscriptionPlanSerializer(sub.plan).data
            data['effective_plan_code'] = sub.plan.code
            data['status'] = sub.status
            data['end_date'] = sub.end_date.isoformat()
        else:
            data['is_active'] = False
            data['plan'] = data.get('plan') or FREE_PLAN_PAYLOAD
        return response.Response(data)


class AdminApprovePaymentAPIView(APIView):
    """POST /api/admin/payment/approve/<id>/"""

    permission_classes = (permissions.IsAdminUser,)

    def post(self, request, pk: int):
        payment = Payment.objects.filter(id=pk).select_related('plan', 'subscription', 'user').first()
        if not payment:
            return response.Response({'message': 'Payment not found.'}, status=status.HTTP_404_NOT_FOUND)
        try:
            sub = ManualPaymentService.approve(payment=payment, reviewer=request.user)
        except ValueError as exc:
            return response.Response({'message': str(exc)}, status=status.HTTP_400_BAD_REQUEST)
        return response.Response(
            {
                'message': 'Payment approved. Subscription activated for 30 days.',
                'payment': PaymentSerializer(payment, context={'request': request}).data,
                'subscription': UserSubscriptionSerializer(sub).data,
            }
        )


class AdminRejectPaymentAPIView(APIView):
    """POST /api/admin/payment/reject/<id>/"""

    permission_classes = (permissions.IsAdminUser,)

    def post(self, request, pk: int):
        payment = Payment.objects.filter(id=pk).select_related('plan', 'subscription').first()
        if not payment:
            return response.Response({'message': 'Payment not found.'}, status=status.HTTP_404_NOT_FOUND)
        note = (request.data.get('note') or request.data.get('admin_note') or '').strip()
        try:
            payment = ManualPaymentService.reject(
                payment=payment,
                reviewer=request.user,
                note=note,
            )
        except ValueError as exc:
            return response.Response({'message': str(exc)}, status=status.HTTP_400_BAD_REQUEST)
        return response.Response(
            {
                'message': 'Payment rejected.',
                'payment': PaymentSerializer(payment, context={'request': request}).data,
            }
        )


class AdminPaymentListAPIView(APIView):
    """GET /api/admin/payments/?status=pending|approved|rejected"""

    permission_classes = (permissions.IsAdminUser,)

    def get(self, request):
        status_filter = (request.query_params.get('status') or '').strip().lower()
        qs = Payment.objects.select_related('user', 'plan').order_by('-created_at')
        if status_filter in {Payment.STATUS_PENDING, Payment.STATUS_APPROVED, Payment.STATUS_REJECTED}:
            qs = qs.filter(status=status_filter)
        return response.Response(
            {
                'results': PaymentSerializer(
                    qs[:200],
                    many=True,
                    context={'request': request},
                ).data,
            }
        )
