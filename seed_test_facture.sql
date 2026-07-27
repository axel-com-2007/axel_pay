-- ============================================================================
-- seed_test_facture.sql — Cheminement complet de test (Adresse → Facture)
-- ============================================================================
-- À exécuter avec psql (les \gset ci-dessous sont des méta-commandes psql,
-- elles ne fonctionnent pas dans pgAdmin/DBeaver — dans ce cas, remplace
-- chaque \gset par une lecture manuelle de l'ID retourné et colle-le dans
-- l'INSERT suivant).
--
-- Utilisation :
--   psql -U <ton_user> -d <ta_base> -f seed_test_facture.sql
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. ADRESSE — nécessaire avant de créer un compteur (id_adresse NOT NULL)
-- ----------------------------------------------------------------------------
INSERT INTO adresses (ville, commune, quartier_description, est_immeuble, date_creation)
VALUES ('Douala', 'Akwa', 'Rue de la Joie, immeuble Le Phare', true, now())
RETURNING id_adresse AS new_id_adresse \gset

-- new_id_adresse contient maintenant l'id généré, réutilisé ci-dessous.


-- ----------------------------------------------------------------------------
-- 2. CLIENT — utilise l'enum_role='Client' et enum_statut_compte='Actif'
-- ----------------------------------------------------------------------------
-- ⚠️ mot_de_passe : ici en clair juste pour le test SQL direct — si tu veux
-- ensuite te connecter via /auth/login/ avec CE compte (et pas seulement lire
-- ses données), il faut y mettre un vrai hash Argon2id généré par ton
-- hash_password() Python, pas ce texte brut. Pour l'instant on suppose que tu
-- consultes juste les données via le compte déjà connecté (id_user=2).
INSERT INTO users (
    nom, prenom, telephone, email, mot_de_passe,
    role, statut_compte, tentatives_connexion_echouees, date_creation
)
VALUES (
    'Mballa', 'Chantal', '+237670000099', 'chantal.mballa@test.cm', 'HASH_A_REMPLACER',
    'Client', 'Actif', 0, now()
)
RETURNING id_user AS new_id_user \gset


-- ----------------------------------------------------------------------------
-- 3. COMPTEUR — rattaché à l'adresse créée en (1)
-- ----------------------------------------------------------------------------
INSERT INTO compteurs (
    numero_compteur, type_compteur, proprietaire_legal, statut,
    date_installation, date_creation, id_adresse
)
VALUES (
    'CMR-TEST-0001', 'POSTPAYE', 'Mballa Chantal', 'Actif',
    '2025-01-15', now(), :new_id_adresse
)
RETURNING id_compteur AS new_id_compteur \gset


-- ----------------------------------------------------------------------------
-- 4. GESTION_COMPTEURS — relie le client au compteur (droit Gestionnaire)
--    C'est cette ligne qui rend le compteur visible via GET /compteurs/
--    pour ce user (get_delegated_compteur_ids dans views.py).
-- ----------------------------------------------------------------------------
INSERT INTO gestion_compteurs (
    id_user, id_compteur, type_droit, statut, date_octroi
)
VALUES (
    :new_id_user, :new_id_compteur, 'Gestionnaire', 'Actif', now()
);


-- ----------------------------------------------------------------------------
-- 5. FACTURE_POSTPAYEE — rattachée au compteur créé en (3)
--    id_facture est un VARCHAR généré manuellement (pas de SERIAL) : on
--    respecte le format métier "FCT-xxxxx".
--    CHECK chk_factures_dates_coherentes exige date_limite >= mois_facturation.
-- ----------------------------------------------------------------------------
INSERT INTO factures_postpayees (
    id_facture, mois_facturation, index_consommation, montant_fcfa,
    statut, date_limite, date_creation, id_compteur
)
VALUES (
    'FCT-TEST-0001', '2026-06-01', 245.50, 38500.00,
    'Impayée', '2026-06-25', now(), :new_id_compteur
);

-- Une deuxième facture, déjà payée, pour tester le filtrage par statut :
INSERT INTO factures_postpayees (
    id_facture, mois_facturation, index_consommation, montant_fcfa,
    statut, date_limite, date_creation, id_compteur
)
VALUES (
    'FCT-TEST-0000', '2026-05-01', 210.00, 33000.00,
    'Payée', '2026-05-25', now(), :new_id_compteur
);


-- ----------------------------------------------------------------------------
-- Récapitulatif — à copier dans Insomnia pour tester
-- ----------------------------------------------------------------------------
\echo '--- IDs créés pour tes tests Insomnia ---'
\echo 'id_adresse  :' :new_id_adresse
\echo 'id_user     :' :new_id_user
\echo 'id_compteur :' :new_id_compteur
\echo 'id_facture  : FCT-TEST-0001 (Impayée) et FCT-TEST-0000 (Payée)'
