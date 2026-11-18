-- =============================================================================
-- schema_postgis.sql
-- DDL complet — GeoAI Inondation Casablanca
-- CRS unique : EPSG:26191 (Lambert Maroc Réel)
-- Schéma    : public
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 0. EXTENSIONS
-- ---------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS postgis;

-- ===========================================================================
-- BLOC 1 — COUCHES VECTEUR SOURCES (OSM / prétraitées)
-- ===========================================================================

-- -----------------------------------------------------------------------
-- 1.1 Bati  (OSM buildings — MULTIPOLYGON)
-- -----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bati (
    fid          SERIAL                              PRIMARY KEY,
    osm_id       BIGINT,
    geom         GEOMETRY(MULTIPOLYGON, 26191)       NOT NULL,
    code         INTEGER,
    fclass       VARCHAR(80),
    name         TEXT,
    type         VARCHAR(120),
    categorie    VARCHAR(80),
    poids        INTEGER,
    surface_m2   DOUBLE PRECISION,
    CONSTRAINT bati_geom_valid CHECK (ST_IsValid(geom))
);
COMMENT ON TABLE bati IS
    'Bâtiments OSM découpés sur Casablanca-Settat, reprojetés EPSG:26191.
     categorie et poids : champs calculés lors du prétraitement.';

-- -----------------------------------------------------------------------
-- 1.2 Route  (OSM roads — MULTILINESTRING → LineString dans le diagramme)
-- -----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS route (
    fid          SERIAL                              PRIMARY KEY,
    osm_id       BIGINT,
    geom         GEOMETRY(MULTILINESTRING, 26191)    NOT NULL,
    nom_rue      TEXT,
    type_voie    VARCHAR(80),
    surface      VARCHAR(80),
    lanes        INTEGER,
    bridge       VARCHAR(20),
    tunnel       VARCHAR(20),
    CONSTRAINT route_geom_valid CHECK (ST_IsValid(geom))
);
COMMENT ON TABLE route IS
    'Réseau routier OSM — EPSG:26191.';

-- -----------------------------------------------------------------------
-- 1.3 CoursEau  (OSM waterways nettoyés + nodés — MULTILINESTRING)
-- -----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS cours_eau (
    fid          SERIAL                              PRIMARY KEY,
    uid          INTEGER,                            -- id séquentiel du notebook (après nodage)
    uid_parent   INTEGER,                            -- uid avant nodage (traçabilité)
    osm_id       BIGINT,
    geom         GEOMETRY(MULTILINESTRING, 26191)    NOT NULL,
    fclass       VARCHAR(40)
                     CHECK (fclass IN ('river','stream','canal','drain')),
    nom          TEXT,
    type_trace   VARCHAR(30)
                     CHECK (type_trace IN ('naturel_presume','artificiel_presume')),
    len_m        DOUBLE PRECISION,
    CONSTRAINT cours_eau_geom_valid CHECK (ST_IsValid(geom))
);
COMMENT ON TABLE cours_eau IS
    'Cours d''eau OSM waterways — version APRÈS nodage (1 449 tronçons).
     uid_parent conserve la référence avant découpe topologique (502 entités source).';

-- -----------------------------------------------------------------------
-- 1.4 OccupationSol  (OSM landuse — MULTIPOLYGON)
-- -----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS occupation_sol (
    fid              SERIAL                          PRIMARY KEY,
    osm_id           BIGINT,
    geom             GEOMETRY(MULTIPOLYGON, 26191)   NOT NULL,
    code             INTEGER,
    fclass           VARCHAR(80),
    landuse_class    VARCHAR(120),
    coef_ruissel     DOUBLE PRECISION
                         CHECK (coef_ruissel BETWEEN 0 AND 1),
    surface_m2       DOUBLE PRECISION,
    CONSTRAINT ocsol_geom_valid CHECK (ST_IsValid(geom))
);
COMMENT ON TABLE occupation_sol IS
    'Occupation du sol OSM (landuse) — EPSG:26191.
     coef_ruissel : coefficient de ruissellement par classe (0–1).';

-- -----------------------------------------------------------------------
-- 1.5 EquipementPOI  (OSM POIs — POINT)
-- -----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS equipement_poi (
    fid          SERIAL                      PRIMARY KEY,
    osm_id       BIGINT,
    geom         GEOMETRY(POINT, 26191)      NOT NULL,
    fclass       VARCHAR(80),
    name         TEXT,
    categorie    VARCHAR(80),
    poids        INTEGER,
    CONSTRAINT equip_geom_valid CHECK (ST_IsValid(geom))
);
COMMENT ON TABLE equipement_poi IS
    'Points d''intérêt OSM (hôpitaux, écoles…) — EPSG:26191.';

-- -----------------------------------------------------------------------
-- 1.6 InfrastructureSecours  (casernes, postes de police… — POINT)
-- -----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS infrastructure_secours (
    fid          SERIAL                      PRIMARY KEY,
    osm_id       BIGINT,
    geom         GEOMETRY(POINT, 26191)      NOT NULL,
    fclass       VARCHAR(80),
    name         TEXT,
    categorie    VARCHAR(80),
    poids        INTEGER,
    CONSTRAINT secours_geom_valid CHECK (ST_IsValid(geom))
);
COMMENT ON TABLE infrastructure_secours IS
    'Infrastructures de secours OSM (casernes de pompiers, hôpitaux…) — EPSG:26191.';

-- ===========================================================================
-- BLOC 2 — ENTITÉS ADMINISTRATIVES
-- ===========================================================================

-- -----------------------------------------------------------------------
-- 2.1 Commune  (limites HCP — limite_casablanca_settat.gpkg)
-- -----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS commune (
    id               SERIAL                          PRIMARY KEY,
    code_commune     VARCHAR(20)                     UNIQUE,   -- NULL tant que non relié aux codes HCP
    nom              VARCHAR(120)                    NOT NULL,
    geom             GEOMETRY(MULTIPOLYGON, 26191)   NOT NULL,
    densite_hab_km2  DOUBLE PRECISION,
    CONSTRAINT commune_geom_valid CHECK (ST_IsValid(geom))
);
COMMENT ON TABLE commune IS
    'Limites communales Casablanca-Settat (OSM, EPSG:26191).
     code_commune : à renseigner par jointure avec les codes du HCP après import.';

-- ===========================================================================
-- BLOC 3 — GRILLE D'ANALYSE
-- ===========================================================================

-- -----------------------------------------------------------------------
-- 3.1 Maille  (grille 100 m × 100 m ou 50 m pour validation)
-- -----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS maille (
    id                  SERIAL                          PRIMARY KEY,
    geom                GEOMETRY(POLYGON, 26191)        NOT NULL,
    centroide           GEOMETRY(POINT, 26191)
                            GENERATED ALWAYS AS (ST_Centroid(geom)) STORED,
    taille_m            INTEGER                         NOT NULL DEFAULT 100,
    commune_id          INTEGER
                            REFERENCES commune(id) ON DELETE SET NULL,
    -- Variables DEM (statistiques zonales raster → maille)
    pente_moy           DOUBLE PRECISION,
    hand_moy            DOUBLE PRECISION,
    twi_moy             DOUBLE PRECISION,
    flux_max            DOUBLE PRECISION,
    depression_moy      DOUBLE PRECISION,
    -- Variables OSM calculées
    pct_impermeable     DOUBLE PRECISION CHECK (pct_impermeable BETWEEN 0 AND 100),
    ruissel_moy         DOUBLE PRECISION CHECK (ruissel_moy BETWEEN 0 AND 1),
    densite_bati        DOUBLE PRECISION,
    densite_routes      DOUBLE PRECISION,
    distance_oued       DOUBLE PRECISION,
    indice_equip        DOUBLE PRECISION,
    distance_secours    DOUBLE PRECISION,
    CONSTRAINT maille_geom_valid CHECK (ST_IsValid(geom))
);
COMMENT ON TABLE maille IS
    'Grille d''analyse spatiale (100 m par défaut, 50 m pour test validation).
     centroide : colonne générée automatiquement (GENERATED ALWAYS STORED).
     Toutes les variables métier sont agrégées ici depuis les couches sources.';

-- ===========================================================================
-- BLOC 4 — SCORING AHP
-- ===========================================================================

-- -----------------------------------------------------------------------
-- 4.1 CalculAHP  (session de calcul AHP)
-- -----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS calcul_ahp (
    id                  SERIAL          PRIMARY KEY,
    date_calcul         TIMESTAMPTZ     NOT NULL DEFAULT now(),
    scenario            VARCHAR(120),
    lambda_max          DOUBLE PRECISION,
    indice_coherence    DOUBLE PRECISION,
    ratio_coherence     DOUBLE PRECISION
                            CHECK (ratio_coherence < 0.1),   -- CR < 0.1 requis
    CONSTRAINT ahp_cr_warn CHECK (ratio_coherence IS NULL OR ratio_coherence < 0.1)
);
COMMENT ON TABLE calcul_ahp IS
    'Session de calcul AHP : paramètres de cohérence (CR < 0,1 requis).
     scenario : libellé de la variante de pondération (ex. "baseline", "sensibilite_pente").';

-- -----------------------------------------------------------------------
-- 4.2 CritereAHP  (poids de chaque variable)
-- -----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS critere_ahp (
    id          SERIAL          PRIMARY KEY,
    calcul_id   INTEGER         NOT NULL REFERENCES calcul_ahp(id) ON DELETE CASCADE,
    variable    VARCHAR(80)     NOT NULL,   -- nom de la colonne dans maille
    sens        CHAR(1)         NOT NULL CHECK (sens IN ('+','-')),
    poids       DOUBLE PRECISION NOT NULL  CHECK (poids BETWEEN 0 AND 1)
);
COMMENT ON TABLE critere_ahp IS
    'Poids AHP normalisé par variable/critère. sens=+ signifie que la valeur élevée augmente le risque.';

-- -----------------------------------------------------------------------
-- 4.3 ComparaisonPaire  (matrice de Saaty)
-- -----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS comparaison_paire (
    calcul_id       INTEGER     NOT NULL REFERENCES calcul_ahp(id) ON DELETE CASCADE,
    critere_i       INTEGER     NOT NULL REFERENCES critere_ahp(id),
    critere_j       INTEGER     NOT NULL REFERENCES critere_ahp(id),
    valeur_saaty    DOUBLE PRECISION NOT NULL
                        CHECK (valeur_saaty BETWEEN 0.111 AND 9.0),  -- 1/9 … 9
    PRIMARY KEY (calcul_id, critere_i, critere_j)
);
COMMENT ON TABLE comparaison_paire IS
    'Matrice de comparaison par paires (échelle de Saaty 1/9–9).';

-- -----------------------------------------------------------------------
-- 4.4 ScoreRisque  (résultat AHP par maille)
-- -----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS score_risque (
    maille_id   INTEGER     NOT NULL REFERENCES maille(id) ON DELETE CASCADE,
    calcul_id   INTEGER     NOT NULL REFERENCES calcul_ahp(id) ON DELETE CASCADE,
    valeur      DOUBLE PRECISION NOT NULL CHECK (valeur BETWEEN 0 AND 1),
    classe      SMALLINT    NOT NULL CHECK (classe BETWEEN 1 AND 5),
    PRIMARY KEY (maille_id, calcul_id)
);
COMMENT ON TABLE score_risque IS
    'Score AHP de vulnérabilité (0–1) et classe (1–5) par maille et par session de calcul.';

-- ===========================================================================
-- BLOC 5 — CLUSTERING
-- ===========================================================================

-- -----------------------------------------------------------------------
-- 5.1 ModeleClustering  (table unique — STI pour KMeans et GMM)
-- -----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS modele_clustering (
    id                  SERIAL          PRIMARY KEY,
    calcul_id           INTEGER         NOT NULL REFERENCES calcul_ahp(id) ON DELETE CASCADE,
    type                VARCHAR(10)     NOT NULL CHECK (type IN ('KMeans','GMM')),
    role                VARCHAR(20)     NOT NULL CHECK (role IN ('baseline','modele'))
                                        DEFAULT 'modele',
    n_clusters          INTEGER         NOT NULL CHECK (n_clusters > 1),
    date_entrainement   TIMESTAMPTZ     NOT NULL DEFAULT now(),
    silhouette          DOUBLE PRECISION,
    davies_bouldin      DOUBLE PRECISION,
    -- Spécifique KMeans
    inertie             DOUBLE PRECISION,
    -- Spécifique GMM
    covariance          VARCHAR(20),
    bic                 DOUBLE PRECISION
);
COMMENT ON TABLE modele_clustering IS
    'Table unique (Single Table Inheritance) pour KMeans (baseline) et GMM (modèle principal).
     Champs spécifiques null pour le type non concerné.';

-- -----------------------------------------------------------------------
-- 5.2 ClusterTypologie  (profil de chaque cluster)
-- -----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS cluster_typologie (
    id              SERIAL          PRIMARY KEY,
    modele_id       INTEGER         NOT NULL REFERENCES modele_clustering(id) ON DELETE CASCADE,
    libelle         VARCHAR(120),
    profil_moyen    JSONB,          -- vecteur des variables normalisées
    ahp_moyen       DOUBLE PRECISION,
    priorite        SMALLINT        CHECK (priorite BETWEEN 1 AND 5),
    intervention    TEXT
);
COMMENT ON TABLE cluster_typologie IS
    'Profil typologique de chaque cluster : vecteur moyen des variables normalisées (JSONB).';

-- -----------------------------------------------------------------------
-- 5.3 AffectationCluster  (maille ↔ modèle ↔ cluster)
-- -----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS affectation_cluster (
    maille_id   INTEGER     NOT NULL REFERENCES maille(id) ON DELETE CASCADE,
    modele_id   INTEGER     NOT NULL REFERENCES modele_clustering(id) ON DELETE CASCADE,
    cluster_id  INTEGER     NOT NULL REFERENCES cluster_typologie(id),
    probabilite DOUBLE PRECISION CHECK (probabilite BETWEEN 0 AND 1),
    PRIMARY KEY (maille_id, modele_id)
);
COMMENT ON TABLE affectation_cluster IS
    'Affectation de chaque maille à un cluster, avec probabilité d''appartenance (GMM/KMeans soft).';

-- ===========================================================================
-- BLOC 6 — PRIORITÉ PAR COMMUNE
-- ===========================================================================

-- -----------------------------------------------------------------------
-- 6.1 PrioriteCommune  (résultat agrégé à l'échelle communale)
-- -----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS priorite_commune (
    commune_id              INTEGER     NOT NULL REFERENCES commune(id) ON DELETE CASCADE,
    calcul_id               INTEGER     NOT NULL REFERENCES calcul_ahp(id) ON DELETE CASCADE,
    cluster_dominant_id     INTEGER     REFERENCES cluster_typologie(id),
    pct_zones_elevees       DOUBLE PRECISION CHECK (pct_zones_elevees BETWEEN 0 AND 100),
    score_moyen             DOUBLE PRECISION CHECK (score_moyen BETWEEN 0 AND 1),
    score_max               DOUBLE PRECISION CHECK (score_max BETWEEN 0 AND 1),
    bati_expose_m2          DOUBLE PRECISION,
    indice_priorite         DOUBLE PRECISION,
    rang_priorite           INTEGER,
    recommandation          TEXT,
    PRIMARY KEY (commune_id, calcul_id)
);
COMMENT ON TABLE priorite_commune IS
    'Synthèse communale : score AHP agrégé, cluster dominant, rang de priorité.';

-- ===========================================================================
-- BLOC 7 — INDEX SPATIAUX GIST
-- ===========================================================================

-- Sources vecteur
CREATE INDEX IF NOT EXISTS idx_bati_geom              ON bati                  USING GIST (geom);
CREATE INDEX IF NOT EXISTS idx_route_geom             ON route                 USING GIST (geom);
CREATE INDEX IF NOT EXISTS idx_cours_eau_geom         ON cours_eau             USING GIST (geom);
CREATE INDEX IF NOT EXISTS idx_ocsol_geom             ON occupation_sol        USING GIST (geom);
CREATE INDEX IF NOT EXISTS idx_equip_geom             ON equipement_poi        USING GIST (geom);
CREATE INDEX IF NOT EXISTS idx_secours_geom           ON infrastructure_secours USING GIST (geom);

-- Entités d'analyse
CREATE INDEX IF NOT EXISTS idx_commune_geom           ON commune               USING GIST (geom);
CREATE INDEX IF NOT EXISTS idx_maille_geom            ON maille                USING GIST (geom);
CREATE INDEX IF NOT EXISTS idx_maille_centroide       ON maille                USING GIST (centroide);

-- ===========================================================================
-- BLOC 8 — INDEX ATTRIBUTAIRES (B-TREE)
-- ===========================================================================

CREATE INDEX IF NOT EXISTS idx_maille_commune         ON maille               (commune_id);
CREATE INDEX IF NOT EXISTS idx_score_maille           ON score_risque         (maille_id);
CREATE INDEX IF NOT EXISTS idx_score_calcul           ON score_risque         (calcul_id);
CREATE INDEX IF NOT EXISTS idx_score_classe           ON score_risque         (classe);
CREATE INDEX IF NOT EXISTS idx_affectation_maille     ON affectation_cluster  (maille_id);
CREATE INDEX IF NOT EXISTS idx_cluster_modele         ON cluster_typologie    (modele_id);
CREATE INDEX IF NOT EXISTS idx_modele_type            ON modele_clustering    (type);
CREATE INDEX IF NOT EXISTS idx_cours_eau_fclass       ON cours_eau            (fclass);
CREATE INDEX IF NOT EXISTS idx_bati_fclass            ON bati                 (fclass);

-- ===========================================================================
-- BLOC 9 — VUES UTILITAIRES
-- ===========================================================================

-- Vue synthèse risque + géométrie maille (utile pour QGIS)
CREATE OR REPLACE VIEW v_maille_risque AS
SELECT
    m.id,
    m.geom,
    m.centroide,
    m.taille_m,
    m.commune_id,
    m.pente_moy, m.hand_moy, m.twi_moy,
    m.pct_impermeable, m.ruissel_moy,
    m.densite_bati, m.densite_routes,
    m.distance_oued, m.indice_equip, m.distance_secours,
    s.valeur    AS score_ahp,
    s.classe    AS classe_risque,
    a.cluster_id,
    ct.libelle  AS cluster_libelle,
    ct.priorite AS cluster_priorite
FROM maille m
LEFT JOIN score_risque s       ON s.maille_id = m.id
LEFT JOIN affectation_cluster a ON a.maille_id = m.id
LEFT JOIN cluster_typologie ct  ON ct.id = a.cluster_id;

COMMENT ON VIEW v_maille_risque IS
    'Vue synthèse : maille + score AHP + cluster. Chargeable directement dans QGIS.';

-- Vue synthèse par commune (pour carte finale)
CREATE OR REPLACE VIEW v_commune_priorite AS
SELECT
    c.id, c.code_commune, c.nom, c.geom,
    c.densite_hab_km2,
    pc.score_moyen, pc.score_max,
    pc.bati_expose_m2, pc.pct_zones_elevees,
    pc.rang_priorite, pc.recommandation,
    ct.libelle AS cluster_dominant_libelle
FROM commune c
LEFT JOIN priorite_commune pc    ON pc.commune_id = c.id
LEFT JOIN cluster_typologie ct   ON ct.id = pc.cluster_dominant_id;

COMMENT ON VIEW v_commune_priorite IS
    'Vue synthèse communale avec rang de priorité et cluster dominant.';

-- ===========================================================================
-- FIN DU DDL
-- ===========================================================================