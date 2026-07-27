from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework_simplejwt.exceptions import InvalidToken, AuthenticationFailed
from .models import Users


class UsersJWTAuthentication(JWTAuthentication):
    """
    Authentification JWT adaptée au modèle `Users` (managed=False, ne
    dérive pas de AbstractUser). On surcharge get_user() pour peupler
    request.user avec une instance `Users` réelle, à partir du claim
    personnalisé `id_user` injecté dans le token (voir LoginView).
    """

    def get_user(self, validated_token):
        id_user = validated_token.get("id_user")
        if id_user is None:
            raise InvalidToken("Token sans id_user.")

        try:
            user = Users.objects.get(pk=id_user)
        except Users.DoesNotExist:
            raise AuthenticationFailed("Utilisateur introuvable.", code="user_not_found")

        if user.statut_compte != "Actif":
            raise AuthenticationFailed("Compte inactif ou non vérifié.", code="user_inactive")

        return user