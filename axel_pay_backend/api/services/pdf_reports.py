# -*- coding: utf-8 -*-
"""
===============================================================================
 pdf_reports.py — Génération de documents PDF (module 9 RGPD & module 11
 Tickets de support)
===============================================================================
Ce module remplace les anciens `TODO INTEGRATION` de `ExportDataView` et
`OuvrirTicketView` : les PDF ne sont plus de simples placeholders, ils sont
réellement construits ici avec ReportLab (pure Python, aucune dépendance
système comme Cairo/Pango — contrairement à WeasyPrint — ce qui le rend
plus simple à déployer).

Deux documents sont produits :
    - `generer_pdf_export_donnees(...)` : récapitulatif du compte + de
      toutes les factures du client, remis en pièce jointe de l'e-mail
      d'export RGPD (CDC 11.3).
    - `generer_pdf_ticket(...)` : fiche PDF du ticket de support ouvert par
      le client, remise en pièce jointe de l'e-mail d'accusé de réception
      (module 11).

Chaque fonction renvoie des `bytes` (contenu brut du PDF), prêts à être
attachés à un `EmailMessage`/`EmailMultiAlternatives` via `.attach(...)`.
===============================================================================
"""

from io import BytesIO

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import mm
from reportlab.platypus import (
    SimpleDocTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
    HRFlowable,
)

_BLEU_ENEO = colors.HexColor("#0B5ED7")
_GRIS_TEXTE = colors.HexColor("#444444")
_GRIS_CLAIR = colors.HexColor("#F2F4F7")


def _styles():
    base = getSampleStyleSheet()
    styles = {
        "titre": ParagraphStyle(
            "TitreEneo", parent=base["Title"], textColor=_BLEU_ENEO, fontSize=18,
        ),
        "sous_titre": ParagraphStyle(
            "SousTitreEneo", parent=base["Heading2"], textColor=_BLEU_ENEO, fontSize=12.5,
            spaceBefore=14, spaceAfter=6,
        ),
        "normal": ParagraphStyle(
            "NormalEneo", parent=base["Normal"], textColor=_GRIS_TEXTE, fontSize=9.5, leading=13,
        ),
        "muted": ParagraphStyle(
            "MutedEneo", parent=base["Normal"], textColor=colors.HexColor("#777777"), fontSize=8.5,
        ),
    }
    return styles


def _entete(elements, styles, titre, sous_titre=None):
    elements.append(Paragraph("ENEO / AxelPay", styles["titre"]))
    elements.append(Paragraph(titre, styles["sous_titre"]))
    if sous_titre:
        elements.append(Paragraph(sous_titre, styles["muted"]))
    elements.append(HRFlowable(width="100%", thickness=1, color=_BLEU_ENEO, spaceAfter=10))


def _pied_de_page(canvas, doc):
    canvas.saveState()
    canvas.setFont("Helvetica", 7.5)
    canvas.setFillColor(colors.HexColor("#999999"))
    canvas.drawString(
        20 * mm, 12 * mm,
        "Document généré automatiquement par AxelPay — confidentiel, à usage strictement personnel.",
    )
    canvas.drawRightString(190 * mm, 12 * mm, f"Page {doc.page}")
    canvas.restoreState()


def _table_standard(data, largeurs, alignements_droite=None):
    table = Table(data, colWidths=largeurs, repeatRows=1)
    style = [
        ("BACKGROUND", (0, 0), (-1, 0), _BLEU_ENEO),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ("FONTSIZE", (0, 0), (-1, -1), 8.5),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, _GRIS_CLAIR]),
        ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#DDDDDD")),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        ("LEFTPADDING", (0, 0), (-1, -1), 6),
    ]
    for idx in (alignements_droite or []):
        style.append(("ALIGN", (idx, 0), (idx, -1), "RIGHT"))
    table.setStyle(TableStyle(style))
    return table


# ==============================================================================
# EXPORT RGPD (CDC 11.3) — récapitulatif de compte + TOUTES les factures
# ==============================================================================

def generer_pdf_export_donnees(user, contrats, compteurs, factures, transactions_prepayees, date_export):
    """
    Construit le PDF envoyé au client lors d'un export de données
    (`ExportDataView`) : profil, contrats/compteurs, puis le récapitulatif
    complet de toutes les factures (postpayé) et recharges (prépayé).

    Paramètres attendus (querysets ou listes d'instances de modèle) :
        user                    : instance Users
        contrats                : itérable de Contrats
        compteurs               : itérable de Compteurs
        factures                : itérable de FacturesPostpayees
        transactions_prepayees  : itérable de TransactionsPrepayees
        date_export             : datetime

    Renvoie : bytes (contenu du PDF).
    """
    buffer = BytesIO()
    doc = SimpleDocTemplate(
        buffer, pagesize=A4,
        topMargin=18 * mm, bottomMargin=18 * mm, leftMargin=20 * mm, rightMargin=20 * mm,
    )
    styles = _styles()
    elements = []

    _entete(
        elements, styles,
        "Export de mes données personnelles",
        f"Généré le {date_export:%d/%m/%Y à %H:%M} — conformité loi n°2010/012 (ANTIC)",
    )

    # ── Profil ────────────────────────────────────────────────────────────
    elements.append(Paragraph("Profil", styles["sous_titre"]))
    profil_data = [
        ["Nom complet", f"{user.prenom} {user.nom}"],
        ["Téléphone", user.telephone or "—"],
        ["E-mail", user.email or "—"],
        ["Quartier", getattr(user, "quartier", None) or "—"],
        ["Situation matrimoniale", getattr(user, "situation_matrimoniale", None) or "—"],
    ]
    elements.append(_table_standard(
        [["Champ", "Valeur"]] + profil_data, [55 * mm, 105 * mm],
    ))

    # ── Contrats & compteurs ─────────────────────────────────────────────
    contrats = list(contrats)
    if contrats:
        elements.append(Paragraph("Contrats", styles["sous_titre"]))
        lignes = [["Numéro de contrat", "Statut", "Date de création"]]
        for c in contrats:
            lignes.append([
                c.numero_contrat,
                c.statut,
                c.date_creation.strftime("%d/%m/%Y") if c.date_creation else "—",
            ])
        elements.append(_table_standard(lignes, [65 * mm, 45 * mm, 50 * mm]))

    compteurs = list(compteurs)
    if compteurs:
        elements.append(Paragraph("Compteurs", styles["sous_titre"]))
        lignes = [["N° compteur", "Type", "Statut"]]
        for cpt in compteurs:
            lignes.append([cpt.numero_compteur, cpt.type_compteur, cpt.statut])
        elements.append(_table_standard(lignes, [65 * mm, 45 * mm, 50 * mm]))

    # ── Récapitulatif de TOUTES les factures ────────────────────────────
    factures = list(factures)
    elements.append(Paragraph(
        f"Factures ({len(factures)})", styles["sous_titre"],
    ))
    if factures:
        lignes = [["N° facture", "Mois", "Montant (FCFA)", "Statut", "Échéance"]]
        total = 0
        for f in sorted(factures, key=lambda x: x.mois_facturation, reverse=True):
            montant = float(f.montant_fcfa or 0)
            total += montant
            lignes.append([
                f.id_facture,
                f.mois_facturation.strftime("%m/%Y") if f.mois_facturation else "—",
                f"{montant:,.0f}".replace(",", " "),
                f.statut,
                f.date_limite.strftime("%d/%m/%Y") if f.date_limite else "—",
            ])
        lignes.append(["", "", "", "Total facturé", f"{total:,.0f} FCFA".replace(",", " ")])
        elements.append(_table_standard(
            lignes, [30 * mm, 22 * mm, 33 * mm, 40 * mm, 30 * mm], alignements_droite=[2],
        ))
    else:
        elements.append(Paragraph("Aucune facture postpayée sur ce compte.", styles["normal"]))

    # ── Recharges prépayées ──────────────────────────────────────────────
    transactions_prepayees = list(transactions_prepayees)
    if transactions_prepayees:
        elements.append(Paragraph(
            f"Recharges prépayées ({len(transactions_prepayees)})", styles["sous_titre"],
        ))
        lignes = [["Date", "Montant (FCFA)", "kWh", "Statut"]]
        for t in sorted(transactions_prepayees, key=lambda x: x.date_transaction, reverse=True)[:100]:
            lignes.append([
                t.date_transaction.strftime("%d/%m/%Y %H:%M") if t.date_transaction else "—",
                f"{float(t.montant_fcfa or 0):,.0f}".replace(",", " "),
                f"{float(t.valeur_kwh or 0):.2f}",
                t.statut_paiement,
            ])
        elements.append(_table_standard(lignes, [45 * mm, 40 * mm, 30 * mm, 40 * mm], alignements_droite=[1]))

    elements.append(Spacer(1, 10))
    elements.append(Paragraph(
        "Ce document constitue l'export complet des données personnelles associées à votre "
        "compte AxelPay, conformément à votre droit d'accès (loi camerounaise n°2010/012 relative "
        "à la cybersécurité et à la cybercriminalité, sous contrôle de l'ANTIC). Pour toute "
        "question, contactez le support depuis l'application.",
        styles["muted"],
    ))

    doc.build(elements, onFirstPage=_pied_de_page, onLaterPages=_pied_de_page)
    return buffer.getvalue()


# ==============================================================================
# TICKET DE SUPPORT (module 11) — fiche PDF jointe à l'e-mail client
# ==============================================================================

def generer_pdf_ticket(ticket_id, user, sujet, description, categorie, priorite, date_ouverture):
    """
    Construit la fiche PDF du ticket de support ouvert par le client
    (`OuvrirTicketView`), jointe à l'e-mail d'accusé de réception envoyé au
    client — une trace écrite et imprimable de sa demande.
    """
    buffer = BytesIO()
    doc = SimpleDocTemplate(
        buffer, pagesize=A4,
        topMargin=18 * mm, bottomMargin=18 * mm, leftMargin=20 * mm, rightMargin=20 * mm,
    )
    styles = _styles()
    elements = []

    _entete(
        elements, styles,
        f"Ticket de support {ticket_id}",
        f"Ouvert le {date_ouverture:%d/%m/%Y à %H:%M}",
    )

    elements.append(_table_standard(
        [
            ["Champ", "Valeur"],
            ["Numéro de ticket", ticket_id],
            ["Client", f"{user.prenom} {user.nom}"],
            ["E-mail", user.email or "—"],
            ["Téléphone", user.telephone or "—"],
            ["Catégorie", categorie],
            ["Priorité", priorite],
            ["Statut", "Ouvert"],
        ],
        [55 * mm, 105 * mm],
    ))

    elements.append(Paragraph("Sujet", styles["sous_titre"]))
    elements.append(Paragraph(sujet, styles["normal"]))

    elements.append(Paragraph("Description du problème", styles["sous_titre"]))
    # Préserve les retours à la ligne saisis par le client.
    description_html = description.replace("\n", "<br/>")
    elements.append(Paragraph(description_html, styles["normal"]))

    elements.append(Spacer(1, 14))
    elements.append(Paragraph(
        "Notre équipe support s'engage à répondre sous 24h ouvrées. Vous pouvez suivre ou "
        "compléter ce ticket en répondant directement à l'e-mail de confirmation reçu.",
        styles["muted"],
    ))

    doc.build(elements, onFirstPage=_pied_de_page, onLaterPages=_pied_de_page)
    return buffer.getvalue()
