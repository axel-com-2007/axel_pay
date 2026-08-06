# -*- coding: utf-8 -*-
"""
===============================================================================
 urls.py — Plateforme Eneo (Gestion des Factures & Recharges)
===============================================================================
Routage de l'app `api`, organisé selon les 9 mêmes modules fonctionnels que
`views.py`. Chaque route est nommée (`name=...`) afin de pouvoir être
référencée via `reverse()` / `reverse_lazy()` ailleurs dans le projet
(templates back-office, tests, génération de liens dans les notifications...).

À inclure dans le `urls.py` racine du projet, par exemple :

    # axel_pay_backend/urls.py
    from django.urls import path, include

    urlpatterns = [
        path("api/", include("api.urls")),
    ]
===============================================================================
"""

from django.urls import path

from .views import (
    # Module 1 — Authentification, profil & préférences
    RegisterView,
    VerifyOTPView,
    LoginView,
    LogoutView,
    RefreshTokenView,
    PasswordResetRequestView,
    PasswordResetConfirmView,
    ChangePhoneNumberView,
    ProfileView,
    UserRechercheView,
    UserConsentView,
    NotificationPreferencesView,
    # Module 2 — Contrats, comptes & compteurs
    ContratListCreateView,
    ContratDetailView,
    ContratCompteursListView,
    ContratFacturesListView,
    CompteurListCreateView,
    CompteurDetailView,
    GestionCompteursView,
    RevokeDelegationView,
    TransferCompteurView,
    AgentTerrainCompteurRegisterView,
    # Module 3 — Client postpayé
    FacturesListView,
    FactureDetailView,
    FactureReçuPDFView,
    ConsommationGraphView,
    SignalerAnomalieFactureView,
    FactureStatutView,
    # Module 4 — Client prépayé
    SoldeCreditView,
    AchatCreditView,
    TokenHistoriqueView,
    AlerteSoldeBasView,
    AlerteTechniqueCompteurView,
    # Module 5 — Paiements & agrégateurs Mobile Money
    InitierPaiementView,
    WebhookPaiementView,
    NotchPayWebhookView,
    PaiementStatutView,
    ReconciliationComptableView,
    RemboursementView,
    # Module 6 — Notifications
    NotificationHistoriqueView,
    DeviceRegisterView,
    DeviceUnregisterView,
    # Module 7 — Back-office administrateur
    AdminDashboardKPIView,
    AdminUserManagementView,
    ImpersonationStartView,
    ImpersonationEndView,
    AuditLogsListView,
    LitigeCreateView,
    LitigeListView,
    LitigeResolveView,
    WebhookLogsListView,
    # Module 8 — Référentiels
    TarifsListView,
    AdressesView,
    # Module 9 — Conformité / RGPD
    ExportDataView,
    DeleteAccountView,
)

app_name = "api"

urlpatterns = [

    # ==========================================================================
    # MODULE 1 — AUTHENTIFICATION, PROFIL & PRÉFÉRENCES (CDC 5.1)
    # ==========================================================================
    path("auth/register/", RegisterView.as_view(), name="register"),
    path("auth/verify-otp/", VerifyOTPView.as_view(), name="verify-otp"),
    path("auth/login/", LoginView.as_view(), name="login"),
    path("auth/logout/", LogoutView.as_view(), name="logout"),
    path("auth/refresh/", RefreshTokenView.as_view(), name="refresh-token"),
    path("auth/password-reset/", PasswordResetRequestView.as_view(), name="password-reset-request"),
    path("auth/password-reset/confirm/", PasswordResetConfirmView.as_view(), name="password-reset-confirm"),
    path("auth/change-phone/", ChangePhoneNumberView.as_view(), name="change-phone"),

    # Recherche par téléphone pour la délégation de compteur/contrat (RG-02) —
    # cf. UserRechercheView. Placée hors de /profile/ car elle porte sur un
    # AUTRE utilisateur que request.user, à des fins de délégation uniquement.
    path("users/recherche/", UserRechercheView.as_view(), name="user-recherche"),

    path("profile/", ProfileView.as_view(), name="profile"),
    path("profile/consent/", UserConsentView.as_view(), name="user-consent"),
    path("profile/compteurs/<int:id_compteur>/notification-preferences/",
         NotificationPreferencesView.as_view(), name="notification-preferences"),

    # ==========================================================================
    # MODULE 2 — CONTRATS, COMPTES & COMPTEURS (CDC 5.1, 5.5 — RG-01 à RG-03)
    # ==========================================================================
    # REFONTE v1.5 : CONTRATS est la nouvelle racine du graphe de propriété
    # (USERS 1—N CONTRATS 1—N COMPTEURS 1—N FACTURES).
    path("contrats/", ContratListCreateView.as_view(), name="contrat-list-create"),
    path("contrats/<int:id_contrat>/", ContratDetailView.as_view(), name="contrat-detail"),
   path("contrats/<int:id_contrat>/compteurs/", ContratCompteursListView.as_view(), name="contrat-compteurs-list"),
    # Factures agrégées, tous compteurs du contrat confondus (filtres :
    # ?statut=Payée|En cours|Impayée, ?id_compteur=X, ?historique_complet=true).
    path("contrats/<int:id_contrat>/factures/", ContratFacturesListView.as_view(), name="contrat-factures-list"),
    path("compteurs/", CompteurListCreateView.as_view(), name="compteur-list-create"),
    path("compteurs/<int:id_compteur>/", CompteurDetailView.as_view(), name="compteur-detail"),
    path("compteurs/<int:id_compteur>/transfert/", TransferCompteurView.as_view(), name="compteur-transfert"),
    path("compteurs/agent-terrain/enregistrement/",
         AgentTerrainCompteurRegisterView.as_view(), name="compteur-agent-terrain-register"),

    # Délégations à un tiers : soit `id_compteur`, soit `id_contrat` dans le
    # payload POST (cf. GestionCompteursSerializer.validate — exclusivité).
    path("delegations/", GestionCompteursView.as_view(), name="delegation-list-create"),
    path("delegations/<int:id_delegation>/revoquer/", RevokeDelegationView.as_view(), name="delegation-revoke"),

    # ==========================================================================
    # MODULE 3 — CLIENT POSTPAYÉ (CDC 5.2)
    # ==========================================================================
    path("compteurs/<int:id_compteur>/factures/", FacturesListView.as_view(), name="factures-list"),
    path("compteurs/<int:id_compteur>/consommation/", ConsommationGraphView.as_view(), name="consommation-graph"),
    path("factures/<str:id_facture>/", FactureDetailView.as_view(), name="facture-detail"),
    path("factures/<str:id_facture>/statut/", FactureStatutView.as_view(), name="facture-statut"),
    path("factures/<str:id_facture>/recu/", FactureReçuPDFView.as_view(), name="facture-recu-pdf"),
    path("factures/<str:id_facture>/signaler-anomalie/",
         SignalerAnomalieFactureView.as_view(), name="facture-signaler-anomalie"),

    # ==========================================================================
    # MODULE 4 — CLIENT PRÉPAYÉ (CDC 5.3)
    # ==========================================================================
    path("compteurs/<int:id_compteur>/solde/", SoldeCreditView.as_view(), name="solde-credit"),
    path("compteurs/<int:id_compteur>/achat-credit/", AchatCreditView.as_view(), name="achat-credit"),
    path("compteurs/<int:id_compteur>/tokens/", TokenHistoriqueView.as_view(), name="token-historique"),
    path("compteurs/<int:id_compteur>/alerte-solde-bas/",
         AlerteSoldeBasView.as_view(), name="alerte-solde-bas"),
    path("compteurs/<int:id_compteur>/alerte-technique/",
         AlerteTechniqueCompteurView.as_view(), name="alerte-technique-compteur"),

    # ==========================================================================
    # MODULE 5 — PAIEMENTS & AGRÉGATEURS MOBILE MONEY (CDC 9 — RG-06 à RG-11)
    # ==========================================================================
    path("paiements/initier/", InitierPaiementView.as_view(), name="paiement-initier"),
    path("paiements/webhook/", WebhookPaiementView.as_view(), name="paiement-webhook"),
    # Point de terminaison dédié NotchPay (cf. api_pour_axelblez.txt) — à
    # renseigner tel quel dans le dashboard NotchPay : /api/webhooks/notchpay/
    path("webhooks/notchpay/", NotchPayWebhookView.as_view(), name="notchpay-webhook"),
    path("paiements/<str:id_paiement>/", PaiementStatutView.as_view(), name="paiement-statut"),
    path("paiements/<str:id_paiement>/rembourser/", RemboursementView.as_view(), name="paiement-remboursement"),
    path("paiements/reconciliation/", ReconciliationComptableView.as_view(), name="paiement-reconciliation"),

    # ==========================================================================
    # MODULE 6 — NOTIFICATIONS (CDC 10)
    # ==========================================================================
    path("notifications/", NotificationHistoriqueView.as_view(), name="notification-historique"),
    path("devices/", DeviceRegisterView.as_view(), name="device-register"),
    path("devices/<int:id_device>/desenregistrer/", DeviceUnregisterView.as_view(), name="device-unregister"),

    # ==========================================================================
    # MODULE 7 — BACK-OFFICE ADMINISTRATEUR (CDC 5.4 — RG-04, RG-05)
    # ==========================================================================
    path("admin/dashboard/kpi/", AdminDashboardKPIView.as_view(), name="admin-dashboard-kpi"),
    path("admin/utilisateurs/", AdminUserManagementView.as_view(), name="admin-user-management"),

    path("admin/impersonation/<int:id_user_cible>/start/",
         ImpersonationStartView.as_view(), name="impersonation-start"),
    path("admin/impersonation/<int:id_user_cible>/end/",
         ImpersonationEndView.as_view(), name="impersonation-end"),

    path("admin/audit-logs/", AuditLogsListView.as_view(), name="audit-logs-list"),
    path("admin/webhook-logs/", WebhookLogsListView.as_view(), name="webhook-logs-list"),

    path("litiges/", LitigeListView.as_view(), name="litige-list"),
    path("litiges/ouvrir/", LitigeCreateView.as_view(), name="litige-create"),
    path("litiges/<str:id_litige>/resoudre/", LitigeResolveView.as_view(), name="litige-resolve"),

    # ==========================================================================
    # MODULE 8 — RÉFÉRENTIELS
    # ==========================================================================
    path("tarifs/", TarifsListView.as_view(), name="tarifs-list"),
    path("adresses/", AdressesView.as_view(), name="adresses-list-create"),

    # ==========================================================================
    # MODULE 9 — CONFORMITÉ / RGPD (CDC 11.3)
    # ==========================================================================
    path("compte/export/", ExportDataView.as_view(), name="compte-export"),
    path("compte/desactiver/", DeleteAccountView.as_view(), name="compte-desactiver"),
]
