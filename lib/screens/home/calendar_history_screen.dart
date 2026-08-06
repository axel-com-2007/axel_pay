// ============================================================
// CALENDRIER "DERNIÈRE MISE À JOUR" → HISTORIQUE SUR PÉRIODE
// ============================================================
// Déclenché depuis le dashboard en tapant sur la boîte grise
// "Dernière mise à jour" (icône calendrier). Flux :
//  1) `CalendarOverlay.pick` ouvre un vrai calendrier moderne en
//     overlay (fond de l'accueil flouté derrière), l'utilisateur
//     choisit une date.
//  2) Une fois la date choisie, `HistoryOptionsScreen` propose 3
//     options pour la période [date choisie -> aujourd'hui] :
//       - Historique des transactions (factures payées + tokens
//         achetés), fusionnées et triées par date
//       - Historique des factures reçues sur la période
//       - Graphique de consommation sur la période
// Toutes les données sont scoppées au compteur ACTIF affiché sur
// l'accueil (même granularité que le reste du dashboard).
// ============================================================

import 'dart:ui';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../data/eneo_repository.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations/animations.dart';
import '../../widgets/app_card.dart';

/// Overlay plein écran affichant un calendrier moderne (mois par mois,
/// sélection d'un jour) par-dessus le reste de l'app floutée.
class CalendarOverlay {
  CalendarOverlay._();

  /// Ouvre l'overlay flouté et renvoie la date choisie (ou `null` si
  /// l'utilisateur annule).
  static Future<DateTime?> pick(BuildContext context) {
    return showGeneralDialog<DateTime>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Choisir une date',
      barrierColor: Colors.black.withOpacity(0.15),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, anim1, anim2) => const SizedBox.shrink(),
      transitionBuilder: (context, anim, secondaryAnim, child) {
        return BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: 10 * anim.value,
            sigmaY: 10 * anim.value,
          ),
          child: FadeTransition(
            opacity: anim,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.94, end: 1).animate(
                CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
              ),
              child: const _CalendarOverlayCard(),
            ),
          ),
        );
      },
    );
  }
}

class _CalendarOverlayCard extends StatefulWidget {
  const _CalendarOverlayCard();

  @override
  State<_CalendarOverlayCard> createState() => _CalendarOverlayCardState();
}

class _CalendarOverlayCardState extends State<_CalendarOverlayCard> {
  late DateTime _moisAffiche;
  DateTime? _selection;

  static const _joursFr = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
  static const _moisFrNoms = [
    'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin',
    'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _moisAffiche = DateTime(now.year, now.month);
  }

  void _changerMois(int delta) {
    setState(() => _moisAffiche = DateTime(_moisAffiche.year, _moisAffiche.month + delta));
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final aujourdhui = DateTime(now.year, now.month, now.day);
    final premierJourMois = DateTime(_moisAffiche.year, _moisAffiche.month, 1);
    // Lundi = 1 ... Dimanche = 7 -> décalage pour démarrer la grille un lundi.
    final decalage = premierJourMois.weekday - 1;
    final nbJours = DateTime(_moisAffiche.year, _moisAffiche.month + 1, 0).day;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: AppShadows.floating,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded, color: AppColors.primaryDark),
                      onPressed: () => _changerMois(-1),
                    ),
                    Text(
                      '${_moisFrNoms[_moisAffiche.month - 1]} ${_moisAffiche.year}',
                      style: AppTextStyles.h3,
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded, color: AppColors.primaryDark),
                      onPressed: () => _changerMois(1),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: _joursFr
                      .map((j) => Expanded(
                            child: Center(
                              child: Text(
                                j,
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 6),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: decalage + nbJours,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    childAspectRatio: 1,
                  ),
                  itemBuilder: (context, index) {
                    if (index < decalage) return const SizedBox();
                    final jour = index - decalage + 1;
                    final date = DateTime(_moisAffiche.year, _moisAffiche.month, jour);
                    final estFutur = date.isAfter(aujourdhui);
                    final estSelectionne = _selection != null &&
                        date.year == _selection!.year &&
                        date.month == _selection!.month &&
                        date.day == _selection!.day;
                    final estAujourdhui = date.year == aujourdhui.year &&
                        date.month == aujourdhui.month &&
                        date.day == aujourdhui.day;
                    return InkWell(
                      borderRadius: BorderRadius.circular(30),
                      onTap: estFutur ? null : () => setState(() => _selection = date),
                      child: Container(
                        margin: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: estSelectionne ? AppColors.primary : Colors.transparent,
                          shape: BoxShape.circle,
                          border: estAujourdhui && !estSelectionne
                              ? Border.all(color: AppColors.primary, width: 1.4)
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '$jour',
                          style: TextStyle(
                            fontWeight: estSelectionne ? FontWeight.w700 : FontWeight.w500,
                            color: estFutur
                                ? AppColors.textMuted.withOpacity(0.4)
                                : estSelectionne
                                    ? Colors.white
                                    : AppColors.textDark,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    onPressed: _selection == null
                        ? null
                        : () => Navigator.of(context).pop(_selection),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      disabledBackgroundColor: AppColors.divider,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.field),
                      ),
                    ),
                    child: const Text('Confirmer', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Les 3 options d'historique proposées une fois la date choisie.
enum _OptionHistorique { transactions, factures, consommation }

/// Page à 3 options affichée après le choix d'une date dans le
/// calendrier : historique des transactions / des factures reçues /
/// graphique de consommation, sur la période [dateChoisie -> aujourd'hui].
class HistoryOptionsScreen extends StatefulWidget {
  final CompteurModel compteur;
  final DateTime dateChoisie;

  const HistoryOptionsScreen({
    super.key,
    required this.compteur,
    required this.dateChoisie,
  });

  @override
  State<HistoryOptionsScreen> createState() => _HistoryOptionsScreenState();
}

class _HistoryOptionsScreenState extends State<HistoryOptionsScreen> {
  final _repo = EneoRepository();
  _OptionHistorique? _optionChoisie;

  int? get _idCompteur => int.tryParse(widget.compteur.id);
  bool get _estPrepaye => widget.compteur.type == TypeCompteur.prepaye;

  DateTime get _debut => DateTime(
        widget.dateChoisie.year,
        widget.dateChoisie.month,
        widget.dateChoisie.day,
      );
  DateTime get _fin {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, 23, 59, 59);
  }

  bool _dansPeriode(DateTime d) => !d.isBefore(_debut) && !d.isAfter(_fin);

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Historique du ${_formatDate(_debut)} à aujourd’hui'),
      ),
      body: SafeArea(
        child: _optionChoisie == null ? _buildChoixOptions() : _buildResultat(),
      ),
    );
  }

  Widget _buildChoixOptions() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Que souhaitez-vous consulter sur cette période ?',
          style: AppTextStyles.bodyMuted,
        ),
        const SizedBox(height: 16),
        _OptionCard(
          icon: Icons.swap_horiz_rounded,
          iconColor: AppColors.primary,
          title: 'Historique des transactions',
          subtitle: 'Factures payées et tokens achetés sur la période',
          onTap: () => setState(() => _optionChoisie = _OptionHistorique.transactions),
        ),
        const SizedBox(height: 12),
        _OptionCard(
          icon: Icons.receipt_long_rounded,
          iconColor: AppColors.secondaryGreenDark,
          title: 'Historique des factures',
          subtitle: 'Les factures reçues sur la période',
          onTap: () => setState(() => _optionChoisie = _OptionHistorique.factures),
        ),
        const SizedBox(height: 12),
        _OptionCard(
          icon: Icons.show_chart_rounded,
          iconColor: AppColors.warning,
          title: 'Graphique de consommation',
          subtitle: 'Évolution de la consommation sur la période',
          onTap: () => setState(() => _optionChoisie = _OptionHistorique.consommation),
        ),
      ],
    );
  }

  Widget _buildResultat() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _optionChoisie = null),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('Changer d’option'),
            ),
          ),
        ),
        Expanded(
          child: switch (_optionChoisie!) {
            _OptionHistorique.transactions => _buildTransactions(),
            _OptionHistorique.factures => _buildFactures(),
            _OptionHistorique.consommation => _buildConsommation(),
          },
        ),
      ],
    );
  }

  // -- Option 1 : transactions (factures payées + tokens achetés) -------

  Widget _buildTransactions() {
    final idCompteur = _idCompteur;
    if (idCompteur == null) {
      return const _MessageVide('Compteur introuvable.');
    }
    return FutureBuilder<List<_EvenementTransaction>>(
      future: _chargerTransactions(idCompteur),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: LottieLoader(size: 64));
        }
        if (snapshot.hasError) {
          return _MessageVide('Impossible de charger l’historique.');
        }
        final evenements = snapshot.data ?? const [];
        if (evenements.isEmpty) {
          return const _MessageVide('Aucune transaction sur cette période.');
        }
        return ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: evenements.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) => evenements[i].build(),
        );
      },
    );
  }

  Future<List<_EvenementTransaction>> _chargerTransactions(int idCompteur) async {
    final evenements = <_EvenementTransaction>[];

    try {
      final facturesResult = await _repo.getFactures(idCompteur, historiqueComplet: true);
      for (final f in facturesResult.data) {
        if (f.statut == StatutFacture.payee && _dansPeriode(f.dateLimite)) {
          evenements.add(_EvenementTransaction(
            date: f.dateLimite,
            titre: 'Facture payée — ${f.moisFacturation}',
            montant: f.montantFcfa,
            icon: Icons.receipt_long_rounded,
          ));
        }
      }
    } catch (_) {
      // Best-effort : on affiche ce qu'on a pu charger par ailleurs.
    }

    if (_estPrepaye) {
      try {
        final transactionsResult = await _repo.getTransactions(idCompteur);
        for (final t in transactionsResult.data) {
          if (_dansPeriode(t.date)) {
            evenements.add(_EvenementTransaction(
              date: t.date,
              titre: 'Achat de token — ${t.valeurKwh.toStringAsFixed(1)} kWh',
              montant: t.montantFcfa,
              icon: Icons.flash_on_rounded,
            ));
          }
        }
      } catch (_) {
        // idem
      }
    }

    evenements.sort((a, b) => b.date.compareTo(a.date));
    return evenements;
  }

  // -- Option 2 : factures reçues sur la période -------------------------

  Widget _buildFactures() {
    final idCompteur = _idCompteur;
    if (idCompteur == null) {
      return const _MessageVide('Compteur introuvable.');
    }
    return FutureBuilder<List<FactureModel>>(
      future: _chargerFactures(idCompteur),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: LottieLoader(size: 64));
        }
        if (snapshot.hasError) {
          return _MessageVide('Impossible de charger les factures.');
        }
        final factures = snapshot.data ?? const [];
        if (factures.isEmpty) {
          return const _MessageVide('Aucune facture reçue sur cette période.');
        }
        return ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: factures.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final f = factures[i];
            return AppCard(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.description_outlined, color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(f.moisFacturation,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                        const SizedBox(height: 2),
                        Text('Échéance : ${_formatDate(f.dateLimite)} • ${f.statutLabel}',
                            style: AppTextStyles.caption),
                      ],
                    ),
                  ),
                  Text(formatFcfa(f.montantFcfa),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<List<FactureModel>> _chargerFactures(int idCompteur) async {
    // Faute de date d'émission distincte côté modèle, on filtre sur la
    // date limite de la facture (seule date disponible sur FactureModel).
    final result = await _repo.getFactures(idCompteur, historiqueComplet: true);
    final factures = result.data.where((f) => _dansPeriode(f.dateLimite)).toList()
      ..sort((a, b) => b.dateLimite.compareTo(a.dateLimite));
    return factures;
  }

  // -- Option 3 : graphique de consommation sur la période ---------------

  Widget _buildConsommation() {
    final idCompteur = _idCompteur;
    if (idCompteur == null) {
      return const _MessageVide('Compteur introuvable.');
    }
    return FutureBuilder<List<ConsommationPoint>>(
      future: _repo.getConsommation(idCompteur),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: LottieLoader(size: 64));
        }
        if (snapshot.hasError) {
          return _MessageVide('Impossible de charger la consommation.');
        }
        final points = (snapshot.data ?? const [])
            .where((p) => _dansPeriode(p.periode))
            .toList()
          ..sort((a, b) => a.periode.compareTo(b.periode));
        if (points.isEmpty) {
          return const _MessageVide('Aucune donnée de consommation sur cette période.');
        }
        return Padding(
          padding: const EdgeInsets.all(20),
          child: AppCard(
            child: SizedBox(
              height: 240,
              child: _GraphiqueConsommationPeriode(points: points),
            ),
          ),
        );
      },
    );
  }
}

/// Un événement affiché dans la liste "Historique des transactions"
/// (facture payée ou achat de token, sources fusionnées).
class _EvenementTransaction {
  final DateTime date;
  final String titre;
  final double montant;
  final IconData icon;

  _EvenementTransaction({
    required this.date,
    required this.titre,
    required this.montant,
    required this.icon,
  });

  Widget build() {
    String jj(int n) => n.toString().padLeft(2, '0');
    final d = '${jj(date.day)}/${jj(date.month)}/${date.year}';
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.secondaryGreenDark.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: AppColors.secondaryGreenDark, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titre, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                const SizedBox(height: 2),
                Text(d, style: AppTextStyles.caption),
              ],
            ),
          ),
          Text(formatFcfa(montant), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
        ],
      ),
    );
  }
}

/// Graphique en barres réutilisant le même correctif que
/// `PostpaidScreen._buildGraphique` (défilement horizontal si les
/// étiquettes de mois ne tiennent pas), pour une plage de dates choisie.
class _GraphiqueConsommationPeriode extends StatelessWidget {
  final List<ConsommationPoint> points;
  const _GraphiqueConsommationPeriode({required this.points});

  @override
  Widget build(BuildContext context) {
    const double slotWidth = 46;
    final double neededWidth = points.length * slotWidth;

    Widget buildChart(double width) {
      return SizedBox(
        width: width,
        child: BarChart(
          BarChartData(
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            alignment: BarChartAlignment.spaceAround,
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  interval: 1,
                  getTitlesWidget: (value, meta) {
                    final i = value.toInt();
                    if (i < 0 || i >= points.length) return const SizedBox();
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SizedBox(
                        width: slotWidth,
                        child: Text(
                          points[i].moisLabel,
                          style: AppTextStyles.caption,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.visible,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            barGroups: List.generate(points.length, (i) {
              return BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: points[i].kwh,
                  color: AppColors.primary,
                  width: 18,
                  borderRadius: BorderRadius.circular(6),
                ),
              ]);
            }),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double availableWidth = constraints.maxWidth;
        if (neededWidth <= availableWidth) {
          return buildChart(availableWidth);
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: buildChart(neededWidth),
        );
      },
    );
  }
}

class _OptionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _OptionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: AppCard(
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: iconColor.withOpacity(0.12), shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: AppTextStyles.caption),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _MessageVide extends StatelessWidget {
  final String message;
  const _MessageVide(this.message);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(message, textAlign: TextAlign.center, style: AppTextStyles.bodyMuted),
      ),
    );
  }
}
