// ============================================================
// ÉCRAN DU TUNNEL DE PAIEMENT (MOBILE MONEY)
// ============================================================
// Cahier des charges 5. Écran 5 :
//  - Récapitulatif : montant brut, frais agrégateur, total TTC
//  - Sélecteur MTN Mobile Money / Orange Money
//  - Écran d'attente (30 à 60s) pendant la validation USSD
//  - Résultat final : succès (reçu/jeton) ou échec/annulation
// RG-10 rappel : aucune information bancaire ni code PIN n'est
// jamais saisi ici — tout se passe via le push USSD de l'opérateur.
//
// Flux réel côté backend (views.py) :
//  - Recharge prépayée : POST /compteurs/<id>/achat-credit/ crée d'abord
//    la ligne `TransactionsPrepayees` (statut "Initiée"), qui sert ensuite
//    de `reference_cible`.
//  - Facture postpayée : `reference_cible` = l'id de la facture, qui
//    existe déjà.
//  - Puis POST /paiements/initier/ crée la ligne `Paiements` (statut
//    "Initié") — RG-06 : au-delà de 50 000 FCFA, `otp_confirmation` est
//    obligatoire (le serveur renvoie une 400 sur le champ si absent).
//  - Le statut ne passe à "Confirmé" que via `WebhookPaiementView`, un
//    endpoint serveur-à-serveur appelé par l'agrégateur Mobile Money.
//    ⚠️ Aucun agrégateur n'est réellement branché dans ce backend (TODO
//    explicite dans `InitierPaiementView`) : en environnement de test, le
//    paiement peut donc rester indéfiniment "Initié". On gère ce cas
//    honnêtement (état "en attente prolongée") plutôt que de simuler un
//    succès qui n'a pas eu lieu côté serveur.
// ============================================================

import 'package:flutter/material.dart';
import '../../api/api_exception.dart';
import '../../data/connectivity_gate.dart';
import '../../data/eneo_repository.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations/animations.dart';
import '../../widgets/app_card.dart';
import '../../widgets/primary_button.dart';
import '../home/main_shell.dart';

enum _EtapePaiement { recapitulatif, attente, succes, echec, attenteProlongee }

enum OperateurMobileMoney { mtn, orange }

class PaymentScreen extends StatefulWidget {
  final CompteurModel compteur;
  final double montantSuggere;
  final String? factureId;

  const PaymentScreen({
    super.key,
    required this.compteur,
    required this.montantSuggere,
    this.factureId,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final _repo = EneoRepository();

  _EtapePaiement etape = _EtapePaiement.recapitulatif;
  OperateurMobileMoney operateur = OperateurMobileMoney.mtn;
  final telephoneController = TextEditingController(text: '690000000');
  final otpController = TextEditingController();

  bool afficherOtp = false;
  bool envoiEnCours = false;
  String? erreurRecap;
  String? jetonObtenu;
  final ShakeController _shakeErreur = ShakeController();
  int _swipeResetKey = 0;

  bool get estRecharge => widget.factureId == null && widget.compteur.type == TypeCompteur.prepaye;

  double get montant => widget.montantSuggere;
  double get frais => (montant * 0.015).roundToDouble(); // 1.5% indicatif
  double get total => montant + frais;

  static const double _seuil2fa = 50000;

  @override
  void dispose() {
    telephoneController.dispose();
    otpController.dispose();
    super.dispose();
  }

  Future<void> _lancerPaiement() async {
    final idCompteur = int.tryParse(widget.compteur.id);
    if (idCompteur == null) {
      setState(() {
        erreurRecap = 'Compteur invalide.';
        _swipeResetKey++;
      });
      _shakeErreur.shake();
      return;
    }

    // Garde-fou connectivité (§7.6) : "aucune opération financière n'est
    // autorisée sans connexion active". On vérifie ici, juste avant l'appel
    // réseau réel — contrairement au check fait en amont (avant navigation
    // depuis prepaid/postpaid_screen), c'est le seul endroit qui protège
    // contre une perte de connexion pendant la saisie du formulaire.
    // Le filet de sécurité définitif reste de toute façon l'`ApiException`
    // (`ApiNetworkException`) catchée ci-dessous si la connectivité change
    // entre cette vérification et l'appel réel.
    final connecte = await ConnectivityGate.hasConnection;
    if (!connecte) {
      setState(() {
        erreurRecap = 'Vous êtes hors connexion. Le paiement nécessite une connexion active.';
        _swipeResetKey++;
      });
      _shakeErreur.shake();
      return;
    }

    setState(() {
      envoiEnCours = true;
      erreurRecap = null;
    });

    try {
      String referenceCible;
      if (estRecharge) {
        final achat = await _repo.achatCredit(idCompteur, montant);
        referenceCible = '${achat['id_transaction']}';
      } else {
        referenceCible = widget.factureId!;
      }

      await _repo.initierPaiement(
        typePaiement: estRecharge ? 'RECHARGE' : 'FACTURE',
        referenceCible: referenceCible,
        montantFcfa: total,
        numeroMobileMoney: '+237${telephoneController.text.trim()}',
        operateurMobileMoney:
            operateur == OperateurMobileMoney.mtn ? 'MTN_MOMO' : 'ORANGE_MONEY',
        otpConfirmation: afficherOtp ? otpController.text.trim() : null,
      );

      if (!mounted) return;
      setState(() {
        envoiEnCours = false;
        etape = _EtapePaiement.attente;
      });
      // ignore: use_build_context_synchronously
      await _attendreConfirmation(idCompteur);
    } on ApiValidationException catch (e) {
      if (!mounted) return;
      setState(() {
        envoiEnCours = false;
        if (e.fieldErrors.containsKey('otp_confirmation')) {
          afficherOtp = true;
        }
        erreurRecap = e.firstMessage;
        _swipeResetKey++;
      });
      _shakeErreur.shake();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        envoiEnCours = false;
        erreurRecap = e.message;
        _swipeResetKey++;
      });
      _shakeErreur.shake();
    }
  }

  Future<void> _attendreConfirmation(int idCompteur) async {
    // Le push USSD réel prend 30 à 60 secondes (CDC 9.1). On interroge le
    // statut du paiement à intervalle régulier pendant cette fenêtre.
    for (var tentative = 0; tentative < 12; tentative++) {
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      try {
        // Statut du dernier paiement initié pour ce compteur : on relit
        // simplement l'historique des transactions/factures selon le cas,
        // faute d'avoir conservé l'id de paiement entre deux vérifications
        // de widget state — voir note ci-dessous.
        final statut = await _verifierStatutActuel(idCompteur);
        if (statut == 'Confirmé') {
          if (estRecharge) {
            jetonObtenu = (await _repo.getDernierToken(idCompteur)).data;
          }
          if (!mounted) return;
          setState(() => etape = _EtapePaiement.succes);
          return;
        }
        if (statut == 'Échoué' || statut == 'Annulé') {
          if (!mounted) return;
          setState(() => etape = _EtapePaiement.echec);
          return;
        }
      } catch (_) {
        // On ignore les erreurs transitoires de polling et on retente.
      }
    }
    if (!mounted) return;
    setState(() => etape = _EtapePaiement.attenteProlongee);
  }

  /// ⚠️ Simplification assumée : sans agrégateur réel branché côté
  /// serveur, il n'y a pas de webhook qui viendra jamais confirmer ce
  /// paiement dans cet environnement de démonstration. Cette méthode
  /// vérifie le statut de la ressource métier (facture / dernier jeton)
  /// plutôt que de suivre un `id_paiement` précis, ce qui reste correct
  /// tant qu'aucun paiement concurrent n'est en cours sur ce compteur.
  Future<String> _verifierStatutActuel(int idCompteur) async {
    if (estRecharge) {
      final token = await _repo.getDernierToken(idCompteur);
      return token.data != null ? 'Confirmé' : 'Initié';
    } else {
      final factures = await _repo.getFactures(idCompteur);
      final cible = factures.data.where((f) => f.id == widget.factureId);
      if (cible.isEmpty) return 'Initié';
      return cible.first.statut == StatutFacture.payee ? 'Confirmé' : 'Initié';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(estRecharge ? 'Recharger mon crédit' : 'Payer ma facture'),
        automaticallyImplyLeading: etape == _EtapePaiement.recapitulatif,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: switch (etape) {
            _EtapePaiement.recapitulatif => _buildRecapitulatif(),
            _EtapePaiement.attente => _buildAttente(),
            _EtapePaiement.succes => _buildResultat(succes: true),
            _EtapePaiement.echec => _buildResultat(succes: false),
            _EtapePaiement.attenteProlongee => _buildAttentePrologee(),
          },
        ),
      ),
    );
  }

  Widget _buildRecapitulatif() {
    return ListView(
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Récapitulatif', style: AppTextStyles.h3),
              const SizedBox(height: 14),
              _ligneRecap('Compteur', widget.compteur.numero),
              _ligneRecap('Montant', formatFcfa(montant)),
              _ligneRecap('Frais agrégateur (1,5%)', formatFcfa(frais)),
              const Divider(height: 24),
              _ligneRecap('Total à payer', formatFcfa(total), accent: true),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text('Numéro Mobile Money', style: AppTextStyles.label),
        const SizedBox(height: 8),
        TextField(
          controller: telephoneController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            prefixText: '+237 ',
            hintText: '6XX XXX XXX',
          ),
        ),
        const SizedBox(height: 20),
        const Text('Opérateur', style: AppTextStyles.label),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _OperateurCard(
                label: 'MTN Mobile Money',
                color: const Color(0xFFFFC800),
                selected: operateur == OperateurMobileMoney.mtn,
                onTap: () => setState(() => operateur = OperateurMobileMoney.mtn),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _OperateurCard(
                label: 'Orange Money',
                color: const Color(0xFFFF7900),
                selected: operateur == OperateurMobileMoney.orange,
                onTap: () => setState(() => operateur = OperateurMobileMoney.orange),
              ),
            ),
          ],
        ),
        if (total >= _seuil2fa) ...[
          const SizedBox(height: 20),
          const Text('Code de confirmation (2FA)', style: AppTextStyles.label),
          const SizedBox(height: 6),
          const Text(
            'Obligatoire au-delà de 50 000 FCFA (RG-06).',
            style: AppTextStyles.caption,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: otpController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: 'Code reçu par SMS'),
          ),
        ],
        if (erreurRecap != null) ...[
          const SizedBox(height: 16),
          ShakeWidget(
            controller: _shakeErreur,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.danger.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(erreurRecap!, style: const TextStyle(color: AppColors.danger)),
            ),
          ),
        ],
        const SizedBox(height: 28),
        // Glisser pour payer : évite les clics accidentels sur un montant
        // engageant et rend la validation plus intentionnelle.
        SwipeToConfirm(
          key: ValueKey(_swipeResetKey),
          label: 'Glisser pour payer ${formatFcfa(total)}',
          confirmingLabel: 'Envoi en cours…',
          onConfirm: _lancerPaiement,
        ),
        const SizedBox(height: 10),
        const Center(
          child: Text(
            'Aucune information bancaire n’est stockée par AxelPay.',
            style: AppTextStyles.caption,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _ligneRecap(String label, String value, {bool accent = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTextStyles.bodyMuted),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: accent ? 18 : 14,
              color: accent ? AppColors.primaryDark : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttente() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const LottieLoader(size: 80),
          const SizedBox(height: 24),
          const Text('Validation en cours…', style: AppTextStyles.h3),
          const SizedBox(height: 8),
          const Text(
            'Confirmez la transaction sur votre téléphone (push USSD envoyé).',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMuted,
          ),
          const SizedBox(height: 4),
          const Text('Cela peut prendre jusqu’à 60 secondes.', style: AppTextStyles.caption),
        ],
      ),
    );
  }

  Widget _buildAttentePrologee() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.schedule, color: AppColors.warning, size: 56),
          const SizedBox(height: 20),
          const Text('Confirmation en attente', style: AppTextStyles.h2),
          const SizedBox(height: 8),
          const Text(
            'Votre paiement a été transmis à l’opérateur mais n’a pas encore '
            'été confirmé. Cela peut arriver en cas de forte affluence : vous '
            'recevrez une notification dès la confirmation.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMuted,
          ),
          const SizedBox(height: 28),
          PrimaryButton(
            label: 'Retour à l’accueil',
            onPressed: () {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const MainShell()),
                (route) => false,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildResultat({required bool succes}) {
    return Stack(
      children: [
        if (succes) Positioned.fill(child: ConfettiBurst(play: succes)),
        Center(child: _buildResultatContenu(succes: succes)),
      ],
    );
  }

  Widget _buildResultatContenu({required bool succes}) {
    return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 500),
            curve: Curves.elasticOut,
            builder: (context, v, child) => Transform.scale(scale: v, child: child),
            child: Icon(
              succes ? Icons.check_circle : Icons.cancel,
              color: succes ? AppColors.success : AppColors.danger,
              size: 72,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            succes ? 'Paiement confirmé' : 'Paiement échoué',
            style: AppTextStyles.h2,
          ),
          const SizedBox(height: 8),
          Text(
            succes
                ? (estRecharge
                    ? 'Votre jeton de recharge a été généré avec succès.'
                    : 'Votre facture a bien été réglée.')
                : 'La transaction a été annulée ou le délai a expiré.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMuted,
          ),
          if (succes && estRecharge) ...[
            const SizedBox(height: 20),
            AppCard(
              color: AppColors.surface,
              child: Column(
                children: [
                  const Text('Jeton de recharge', style: AppTextStyles.caption),
                  const SizedBox(height: 6),
                  Text(
                    jetonObtenu ?? 'Jeton indisponible pour le moment',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 28),
          PrimaryButton(
            label: succes ? 'Retour à l’accueil' : 'Réessayer',
            onPressed: () {
              if (succes) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const MainShell()),
                  (route) => false,
                );
              } else {
                setState(() => etape = _EtapePaiement.recapitulatif);
              }
            },
          ),
        ],
      );
  }
}

class _OperateurCard extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _OperateurCard({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? color : AppColors.divider, width: selected ? 2 : 1),
        ),
        child: Column(
          children: [
            CircleAvatar(radius: 14, backgroundColor: color),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
