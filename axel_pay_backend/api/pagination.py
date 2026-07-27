# -*- coding: utf-8 -*-
"""
===============================================================================
 pagination.py — Plateforme Eneo
===============================================================================
Plusieurs tables du modèle de données sont explicitement Append-Only
(AuditLogs RG-04, WebhookLogs RG-09, TransactionsPrepayees RG-12,
UserConsentLogs RG-12) : elles ne font que grossir, sans jamais être purgées.
Sans pagination, les vues de liste correspondantes (`AuditLogsListView`,
`WebhookLogsListView`, `TokenHistoriqueView`, ...) tenteraient de sérialiser
l'intégralité de la table en une seule réponse HTTP — un problème de
performance qui s'aggrave mécaniquement avec le temps.

`StandardResultsSetPagination` centralise une pagination par défaut
raisonnable, réutilisable sur toutes les vues de liste du module.
"""

from rest_framework.pagination import PageNumberPagination


class StandardResultsSetPagination(PageNumberPagination):
    page_size = 20
    page_size_query_param = "page_size"
    max_page_size = 100
