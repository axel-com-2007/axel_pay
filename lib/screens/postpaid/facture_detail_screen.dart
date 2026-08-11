// ============================================================
// ÉCRAN DÉTAIL FACTURE — REPRÉSENTATION ENEO SIMPLIFIÉE
// ============================================================
// Affiche une facture complète (style billet ENEO) avec :
//   - Logo Axel Pay
//   - Informations client (nom, adresse, ville)
//   - Numéro de compteur
//   - Ancien index / Nouveau index / Index à payer
//   - Dates de relevé et de facturation
//   - Bouton Imprimer + Télécharger PDF
//
// ⚠️  DÉPENDANCES à ajouter dans pubspec.yaml :
//       pdf: ^3.10.8
//       printing: ^5.13.1
// ============================================================

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../design_system/cards/app_card.dart';
import '../../design_system/colors/app_colors.dart';
import '../../design_system/spacing/app_spacing.dart';
import '../../design_system/typography/app_typography.dart';
import '../../models/models.dart';

class FactureDetailPage extends StatelessWidget {
  final FactureModel facture;
  final CompteurModel compteur;
  final String nomClient;

  const FactureDetailPage({
    super.key,
    required this.facture,
    required this.compteur,
    required this.nomClient,
  });

  // ----------------------------------------------------------------
  // Helpers
  // ----------------------------------------------------------------

  static const List<String> _mois = [
    'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
    'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
  ];

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')} ${_mois[d.month - 1]} ${d.year}';

  /// Consommation à payer : nouveau − ancien si disponibles, sinon
  /// on retombe sur indexConsommation (champ existant).
  double get _indexAPayer {
    if (facture.indexNouveau != null && facture.indexAncien != null) {
      return facture.indexNouveau! - facture.indexAncien!;
    }
    return facture.indexConsommation;
  }

  Color get _couleurStatut {
    switch (facture.statut) {
      case StatutFacture.payee:
        return AppColors.success;
      case StatutFacture.enCours:
        return AppColors.warning;
      case StatutFacture.impayee:
        return AppColors.danger;
    }
  }

  // ----------------------------------------------------------------
  // Génération PDF
  // ----------------------------------------------------------------

  Future<Uint8List> _genererPdf() async {
    final doc = pw.Document();
    final blue = PdfColor.fromHex('#0A5FFF');
    final dark = PdfColor.fromHex('#10182B');
    final grey = PdfColor.fromHex('#5B6472');
    final border = PdfColor.fromHex('#E2E8F0');

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // En-tête
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('AXEL PAY',
                  style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: blue)),
              pw.Text('Plateforme de gestion électrique',
                  style: pw.TextStyle(fontSize: 10, color: grey)),
            ]),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text('FACTURE D\'ÉLECTRICITÉ',
                  style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: dark)),
              pw.Text(facture.moisFacturation,
                  style: pw.TextStyle(fontSize: 11, color: grey)),
              pw.SizedBox(height: 4),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: pw.BoxDecoration(
                  color: facture.statut == StatutFacture.payee
                      ? PdfColor.fromHex('#DCFCE7')
                      : facture.statut == StatutFacture.enCours
                          ? PdfColor.fromHex('#FEF9C3')
                          : PdfColor.fromHex('#FEE2E2'),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Text(facture.statutLabel,
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: facture.statut == StatutFacture.payee
                          ? PdfColor.fromHex('#16A34A')
                          : facture.statut == StatutFacture.enCours
                              ? PdfColor.fromHex('#CA8A04')
                              : PdfColor.fromHex('#DC2626'),
                    )),
              ),
            ]),
          ]),
          pw.Divider(color: border, height: 32),

          // Infos client
          _pdfSection(titre: 'INFORMATIONS CLIENT', border: border, blue: blue, lignes: [
            _pdfRow('Nom', nomClient, grey, dark),
            if (compteur.adresse.isNotEmpty) _pdfRow('Adresse', compteur.adresse, grey, dark),
            if (compteur.ville != null && compteur.ville!.isNotEmpty)
              _pdfRow('Ville', compteur.ville!, grey, dark),
          ]),
          pw.SizedBox(height: 14),

          // Infos compteur
          _pdfSection(titre: 'INFORMATIONS COMPTEUR', border: border, blue: blue, lignes: [
            _pdfRow('N° Compteur', compteur.numero, grey, dark),
          ]),
          pw.SizedBox(height: 14),

          // Relevé
          _pdfSection(titre: 'RELEVÉ DE CONSOMMATION', border: border, blue: blue, lignes: [
            if (facture.dateReleve != null)
              _pdfRow('Date de relevé', _fmtDate(facture.dateReleve!), grey, dark),
            _pdfRow(
              'Ancien index',
              facture.indexAncien != null
                  ? '${facture.indexAncien!.toStringAsFixed(0)} kWh'
                  : 'Premier relevé',
              grey, dark,
            ),
            if (facture.indexNouveau != null)
              _pdfRow('Nouveau index',
                  '${facture.indexNouveau!.toStringAsFixed(0)} kWh', grey, dark),
            _pdfRowBold('Index à payer',
                '${_indexAPayer.toStringAsFixed(0)} kWh', blue, dark),
          ]),
          pw.SizedBox(height: 14),

          // Facturation
          _pdfSection(titre: 'FACTURATION', border: border, blue: blue, lignes: [
            _pdfRow('Période facturée', facture.moisFacturation, grey, dark),
            _pdfRow('Date limite', _fmtDate(facture.dateLimite), grey, dark),
          ]),
          pw.SizedBox(height: 24),

          // Montant total
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(18),
            decoration: pw.BoxDecoration(color: blue, borderRadius: pw.BorderRadius.circular(8)),
            child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text('MONTANT À PAYER',
                  style: pw.TextStyle(color: PdfColors.white, fontSize: 13, fontWeight: pw.FontWeight.bold)),
              pw.Text('${formatFcfa(facture.montantFcfa)} FCFA',
                  style: pw.TextStyle(color: PdfColors.white, fontSize: 18, fontWeight: pw.FontWeight.bold)),
            ]),
          ),

          pw.Spacer(),
          pw.Divider(color: border, height: 24),
          pw.Text('Document généré par Axel Pay — ${_fmtDate(DateTime.now())}',
              style: pw.TextStyle(fontSize: 8, color: grey),
              textAlign: pw.TextAlign.center),
        ],
      ),
    ));

    return doc.save();
  }

  pw.Widget _pdfSection({
    required String titre,
    required List<pw.Widget> lignes,
    required PdfColor border,
    required PdfColor blue,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
          border: pw.Border.all(color: border),
          borderRadius: pw.BorderRadius.circular(6)),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: pw.BoxDecoration(
              color: blue,
              borderRadius: const pw.BorderRadius.only(
                  topLeft: pw.Radius.circular(5), topRight: pw.Radius.circular(5))),
          child: pw.Text(titre,
              style: pw.TextStyle(
                  color: PdfColors.white, fontSize: 9, fontWeight: pw.FontWeight.bold)),
        ),
        pw.Padding(
            padding: const pw.EdgeInsets.all(12),
            child: pw.Column(children: lignes)),
      ]),
    );
  }

  pw.Widget _pdfRow(String label, String value, PdfColor grey, PdfColor dark) =>
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 5),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 10, color: grey)),
          pw.Text(value, style: pw.TextStyle(fontSize: 10, color: dark)),
        ]),
      );

  pw.Widget _pdfRowBold(String label, String value, PdfColor blue, PdfColor dark) =>
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 4),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(label,
              style: pw.TextStyle(
                  fontSize: 11, fontWeight: pw.FontWeight.bold, color: blue)),
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: 11, fontWeight: pw.FontWeight.bold, color: dark)),
        ]),
      );

  // ----------------------------------------------------------------
  // Actions
  // ----------------------------------------------------------------

  Future<void> _imprimer(BuildContext context) async {
    try {
      await Printing.layoutPdf(
        onLayout: (_) => _genererPdf(),
        name: 'Facture_${facture.moisFacturation.replaceAll(' ', '_')}_${compteur.numero}',
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erreur impression : $e')));
    }
  }

  Future<void> _telecharger(BuildContext context) async {
    try {
      final bytes = await _genererPdf();
      await Printing.sharePdf(
        bytes: bytes,
        filename:
            'Facture_${facture.moisFacturation.replaceAll(' ', '_')}_${compteur.numero}.pdf',
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erreur téléchargement : $e')));
    }
  }

  // ----------------------------------------------------------------
  // UI Flutter
  // ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Détail de la facture'),
        actions: [
          IconButton(
            tooltip: 'Imprimer',
            icon: const Icon(Icons.print_outlined),
            onPressed: () => _imprimer(context),
          ),
          IconButton(
            tooltip: 'Télécharger PDF',
            icon: const Icon(Icons.download_outlined),
            onPressed: () => _telecharger(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── En-tête logo ─────────────────────────────────────
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(AppRadius.field),
                    ),
                    child: const Center(
                      child: Text('AP',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text('AXEL PAY',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                          letterSpacing: 2)),
                  const SizedBox(height: 2),
                  Text('Plateforme de gestion électrique',
                      style: AppTextStyles.caption),
                  const SizedBox(height: 14),
                  const Text('FACTURE D\'ÉLECTRICITÉ',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1)),
                  const SizedBox(height: 2),
                  Text(facture.moisFacturation, style: AppTextStyles.bodyMuted),
                  const SizedBox(height: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(
                      color: _couleurStatut.withOpacity(0.12),
                      borderRadius:
                          BorderRadius.circular(AppRadius.chip),
                    ),
                    child: Text(
                      facture.statutLabel,
                      style: TextStyle(
                          color: _couleurStatut,
                          fontWeight: FontWeight.w700,
                          fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // ── Informations client ───────────────────────────────
            _Section(
              titre: 'INFORMATIONS CLIENT',
              lignes: [
                _Ligne(label: 'Nom', valeur: nomClient),
                if (compteur.adresse.isNotEmpty)
                  _Ligne(label: 'Adresse', valeur: compteur.adresse),
                if (compteur.ville != null && compteur.ville!.isNotEmpty)
                  _Ligne(label: 'Ville', valeur: compteur.ville!),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            // ── Informations compteur ─────────────────────────────
            _Section(
              titre: 'INFORMATIONS COMPTEUR',
              lignes: [
                _Ligne(label: 'N° Compteur', valeur: compteur.numero),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            // ── Relevé de consommation ────────────────────────────
            _Section(
              titre: 'RELEVÉ DE CONSOMMATION',
              lignes: [
                if (facture.dateReleve != null)
                  _Ligne(
                      label: 'Date de relevé',
                      valeur: _fmtDate(facture.dateReleve!)),
                _Ligne(
                  label: 'Ancien index',
                  valeur: facture.indexAncien != null
                      ? '${facture.indexAncien!.toStringAsFixed(0)} kWh'
                      : 'Premier relevé',
                ),
                if (facture.indexNouveau != null)
                  _Ligne(
                      label: 'Nouveau index',
                      valeur:
                          '${facture.indexNouveau!.toStringAsFixed(0)} kWh'),
                _Ligne(
                  label: 'Index à payer',
                  valeur: '${_indexAPayer.toStringAsFixed(0)} kWh',
                  gras: true,
                  couleurValeur: AppColors.primary,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            // ── Facturation ───────────────────────────────────────
            _Section(
              titre: 'FACTURATION',
              lignes: [
                _Ligne(label: 'Période facturée', valeur: facture.moisFacturation),
                _Ligne(
                    label: 'Date limite',
                    valeur: _fmtDate(facture.dateLimite)),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            // ── Montant ───────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('MONTANT À PAYER',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold)),
                  Text('${formatFcfa(facture.montantFcfa)} FCFA',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // ── Boutons impression / téléchargement ───────────────
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _imprimer(context),
                  icon: const Icon(Icons.print_outlined, size: 18),
                  label: const Text('Imprimer'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppColors.primary),
                    foregroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppRadius.button)),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _telecharger(context),
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('Télécharger PDF'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppRadius.button)),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: AppSpacing.md),

            Text('Document généré par Axel Pay',
                style: AppTextStyles.caption,
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Widgets internes
// ─────────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String titre;
  final List<Widget> lignes;

  const _Section({required this.titre, required this.lignes});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // En-tête coloré
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
          ),
          child: Text(titre,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8)),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: lignes),
        ),
      ]),
    );
  }
}

class _Ligne extends StatelessWidget {
  final String label;
  final String valeur;
  final bool gras;
  final Color? couleurValeur;

  const _Ligne({
    required this.label,
    required this.valeur,
    this.gras = false,
    this.couleurValeur,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(label,
                style: AppTextStyles.bodyMuted
                    .copyWith(fontSize: 13)),
          ),
          Expanded(
            child: Text(valeur,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      gras ? FontWeight.bold : FontWeight.w500,
                  color: couleurValeur ?? AppColors.textDark,
                ),
                textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}
