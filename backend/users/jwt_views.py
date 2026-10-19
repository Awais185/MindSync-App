from rest_framework.permissions import AllowAny
from rest_framework.parsers import JSONParser
from rest_framework_simplejwt.views import TokenRefreshView

from users.openapi_auth import token_refresh_schema


class DocumentedTokenRefreshView(TokenRefreshView):
    permission_classes = (AllowAny,)
    parser_classes = (JSONParser,)

    @token_refresh_schema
    def post(self, request, *args, **kwargs):
        return super().post(request, *args, **kwargs)
