from api.models import TransactionsPrepayees, Compteurs
from django.utils import timezone

compteur = Compteurs.objects.first()
print("Compteur utilisé :", compteur)

tx = TransactionsPrepayees.objects.create(
    id_transaction="TX-TEST-0001",
    montant_fcfa=2000,
    prix_kwh_applique=95.5,
    valeur_kwh=20.94,
    statut_paiement="Initiée",
    date_transaction=timezone.now(),
    id_compteur=compteur,
)
print("Transaction créée :", tx.id_transaction)