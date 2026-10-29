-- =============================================================================
-- SCHÉMA POSTGIS — GÉOAI INONDATION CASABLANCA
-- Projet : Évaluation du Risque d'Inondation par SIG & IA
-- Auteur : Siham Bouzagrar
-- Base   : geoai_casablanca
-- SRID   : 26191 (Merchich Nord Maroc — Métrique)
-- =============================================================================

-- 0. EXTENSIONS POSTGIS
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_raster;

-- 1. CRÉATION DU SCHÉMA DÉDIÉ
CREATE SCHEMA IF NOT EXISTS geoai;
SET search_path = geoai, public;

-- ===========================================================================
-- BLOC A — MÉTADONNÉES & TRAÇABILITÉ (AVEC CLÉ ÉTRANGÈRE)
-- ===========================================================================

-- A1. Référentiel des sources de données
CREATE TABLE IF NOT EXISTS geoai.source_donnee (
    id                SERIAL          PRIMARY KEY,
    nom               VARCHAR(120)    NOT NULL,
    source            VARCHAR(120)    NOT NULL,
    format            VARCHAR(60),
    licence           VARCHAR(120),
    crs_origine       VARCHAR(30),
    date_acquisition  DATE            DEFAULT CURRENT_DATE
);
COMMENT ON TABLE geoai.source_donnee IS 'Référentiel des sources de données (OSM, Overpass, CartoMaroc, HCP)';

-- A2. Couches brutes importées (Clé étrangère FK vers source_donnee)
CREATE TABLE IF NOT EXISTS geoai.couche_brute (
    id            SERIAL          PRIMARY KEY,
    nom           VARCHAR(120)    NOT NULL,
    format        VARCHAR(60),
    id_source     INTEGER         REFERENCES geoai.source_donnee(id) ON DELETE SET NULL
);
COMMENT ON TABLE geoai.couche_brute IS 'Inventaire des couches brutes avec clé étrangère vers source_donnee';

-- ===========================================================================
-- BLOC B — DONNÉES VECTEUR NETTOYÉES (EPSG:26191)
-- ===========================================================================

-- B1. Bâtiments (Bati) — MULTIPOLYGON
CREATE TABLE IF NOT EXISTS geoai.bati (
    id                  SERIAL                          PRIMARY KEY,
    osm_id              BIGINT,
    code                INTEGER,
    fclass              VARCHAR(80),
    name                TEXT,
    type                VARCHAR(120),
    surface_m2          FLOAT,
    hauteur_estimee_m   FLOAT,
    classe_bati_3cas    VARCHAR(80),
    geom                GEOMETRY(MULTIPOLYGON, 26191)   NOT NULL,
    CONSTRAINT bati_geom_valid CHECK (ST_IsValid(geom))
);
COMMENT ON TABLE geoai.bati IS 'Bâti Casablanca-Settat enrichi (surface, hauteur estimée, 3 classes), SRID 26191';

-- B2. Routes (Route Overpass) — MULTILINESTRING
CREATE TABLE IF NOT EXISTS geoai.route (
    id            SERIAL                              PRIMARY KEY,
    osm_id        BIGINT,
    nom_rue       TEXT,
    type_voie     VARCHAR(80),
    surface       VARCHAR(80),
    lanes         VARCHAR(20),
    bridge        VARCHAR(20),
    tunnel        VARCHAR(20),
    geom          GEOMETRY(MULTILINESTRING, 26191)    NOT NULL,
    CONSTRAINT route_geom_valid CHECK (ST_IsValid(geom))
);
COMMENT ON TABLE geoai.route IS 'Réseau routier Overpass Casablanca, SRID 26191';

-- B3. Occupation du Sol (Landuse) — MULTIPOLYGON
CREATE TABLE IF NOT EXISTS geoai.occupation_sol (
    id            SERIAL                          PRIMARY KEY,
    osm_id        BIGINT,
    code          INTEGER,
    fclass        VARCHAR(80),
    name          TEXT,
    geom          GEOMETRY(MULTIPOLYGON, 26191)   NOT NULL,
    CONSTRAINT ocsol_geom_valid CHECK (ST_IsValid(geom))
);
COMMENT ON TABLE geoai.occupation_sol IS 'Occupation du sol OSM (landuse) Casablanca-Settat, SRID 26191';

-- B4. Équipements / POI — POINT
CREATE TABLE IF NOT EXISTS geoai.equipement (
    id            SERIAL                      PRIMARY KEY,
    osm_id        BIGINT,
    code          INTEGER,
    fclass        VARCHAR(80),
    name          TEXT,
    geom          GEOMETRY(POINT, 26191)      NOT NULL,
    CONSTRAINT equip_geom_valid CHECK (ST_IsValid(geom))
);
COMMENT ON TABLE geoai.equipement IS 'Équipements et POI (écoles, santé, etc.), SRID 26191';

-- B5. Infrastructures de Secours & Casernes — POINT
CREATE TABLE IF NOT EXISTS geoai.caserne (
    id            SERIAL                      PRIMARY KEY,
    osm_id        BIGINT,
    code          INTEGER,
    fclass        VARCHAR(80),
    name          TEXT,
    calming       VARCHAR(80),
    geom          GEOMETRY(POINT, 26191)      NOT NULL,
    CONSTRAINT caserne_geom_valid CHECK (ST_IsValid(geom))
);
COMMENT ON TABLE geoai.caserne IS 'Postes de secours, casernes et santé, SRID 26191';

-- B6. Oueds / Réseau Hydrographique — MULTILINESTRING
CREATE TABLE IF NOT EXISTS geoai.oued (
    id            SERIAL                              PRIMARY KEY,
    name          TEXT,
    geom          GEOMETRY(MULTILINESTRING, 26191)    NOT NULL,
    CONSTRAINT oued_geom_valid CHECK (ST_IsValid(geom))
);
COMMENT ON TABLE geoai.oued IS 'Oueds CartoMaroc dédoublonnés et reprojetés, SRID 26191';

-- B7. Population HCP par commune
CREATE TABLE IF NOT EXISTS geoai.population_hcp (
    id              SERIAL          PRIMARY KEY,
    code_commune    VARCHAR(20)     NOT NULL UNIQUE,
    commune         VARCHAR(120),
    province        VARCHAR(120),
    population      INTEGER,
    superficie_km2  FLOAT,
    densite_hab_km2 FLOAT
);
COMMENT ON TABLE geoai.population_hcp IS 'Données démographiques HCP par commune';

-- ===========================================================================
-- BLOC C — DONNÉES RASTER MNT
-- ===========================================================================
CREATE TABLE IF NOT EXISTS geoai.mnt (
    rid           SERIAL          PRIMARY KEY,
    rast          RASTER          NOT NULL,
    filename      TEXT
);

-- ===========================================================================
-- BLOC D — MAILLES D'ANALYSE (Grille de calcul)
-- ===========================================================================
CREATE TABLE IF NOT EXISTS geoai.maille (
    id                        SERIAL                          PRIMARY KEY,
    code_maille               VARCHAR(50)                     UNIQUE,
    densite_bati              FLOAT,                          -- surface bâtie / km²
    densite_routes            FLOAT,                          -- km routes / km²
    densite_population        FLOAT,                          -- hab / km²
    nb_equip                  INTEGER,
    distance_oued             FLOAT,                          -- distance minimale en mètres
    taux_impermeabilisation   FLOAT,
    pente_moyenne             FLOAT,
    geom                      GEOMETRY(POLYGON, 26191)        NOT NULL,
    CONSTRAINT maille_geom_valid CHECK (ST_IsValid(geom))
);

-- ===========================================================================
-- BLOC E — RISQUE, AHP ET CLUSTERING (CLÉS ÉTRANGÈRES)
-- ===========================================================================
CREATE TABLE IF NOT EXISTS geoai.score_risque (
    id            SERIAL          PRIMARY KEY,
    id_maille     INTEGER         NOT NULL REFERENCES geoai.maille(id) ON DELETE CASCADE,
    valeur        FLOAT           NOT NULL CHECK (valeur BETWEEN 0 AND 1),
    classe        SMALLINT        NOT NULL CHECK (classe BETWEEN 1 AND 5),
    methode       VARCHAR(60)     DEFAULT 'AHP'
);

CREATE TABLE IF NOT EXISTS geoai.calcul_ahp (
    id                  SERIAL          PRIMARY KEY,
    facteur             VARCHAR(80)     NOT NULL,
    poids_normalise     FLOAT           NOT NULL CHECK (poids_normalise BETWEEN 0 AND 1),
    ratio_coherence     FLOAT
);

CREATE TABLE IF NOT EXISTS geoai.cluster_typologie (
    id            SERIAL          PRIMARY KEY,
    id_maille     INTEGER         NOT NULL REFERENCES geoai.maille(id) ON DELETE CASCADE,
    algorithme    VARCHAR(20)     NOT NULL CHECK (algorithme IN ('KMeans','FCM')),
    cluster_id    SMALLINT        NOT NULL,
    appartenance  FLOAT           CHECK (appartenance BETWEEN 0 AND 1),
    profil_moyen  JSONB
);

CREATE TABLE IF NOT EXISTS geoai.zone_intervention (
    id            SERIAL                          PRIMARY KEY,
    id_cluster    INTEGER                         REFERENCES geoai.cluster_typologie(id),
    priorite      SMALLINT                        NOT NULL CHECK (priorite BETWEEN 1 AND 5),
    intervention  TEXT,
    geom          GEOMETRY(MULTIPOLYGON, 26191)   NOT NULL,
    CONSTRAINT zone_geom_valid CHECK (ST_IsValid(geom))
);

CREATE TABLE IF NOT EXISTS geoai.itineraire_secours (
    id            SERIAL                              PRIMARY KEY,
    id_caserne    INTEGER                             REFERENCES geoai.caserne(id),
    id_zone       INTEGER                             REFERENCES geoai.zone_intervention(id),
    distance_m    FLOAT,
    resilient     BOOLEAN                             DEFAULT FALSE,
    geom          GEOMETRY(MULTILINESTRING, 26191)    NOT NULL,
    CONSTRAINT itin_geom_valid CHECK (ST_IsValid(geom))
);

-- ===========================================================================
-- BLOC F — INDEX SPATIAUX GIST
-- ===========================================================================
CREATE INDEX IF NOT EXISTS sidx_bati_geom              ON geoai.bati                USING GIST (geom);
CREATE INDEX IF NOT EXISTS sidx_route_geom             ON geoai.route               USING GIST (geom);
CREATE INDEX IF NOT EXISTS sidx_occupation_sol_geom    ON geoai.occupation_sol      USING GIST (geom);
CREATE INDEX IF NOT EXISTS sidx_equipement_geom        ON geoai.equipement          USING GIST (geom);
CREATE INDEX IF NOT EXISTS sidx_caserne_geom           ON geoai.caserne             USING GIST (geom);
CREATE INDEX IF NOT EXISTS sidx_oued_geom              ON geoai.oued                USING GIST (geom);
CREATE INDEX IF NOT EXISTS sidx_maille_geom            ON geoai.maille              USING GIST (geom);
CREATE INDEX IF NOT EXISTS sidx_zone_intervention_geom ON geoai.zone_intervention   USING GIST (geom);
CREATE INDEX IF NOT EXISTS sidx_itineraire_geom        ON geoai.itineraire_secours  USING GIST (geom);
