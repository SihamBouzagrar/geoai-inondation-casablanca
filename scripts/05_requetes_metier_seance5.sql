-- =============================================================================
-- REQUÊTES SPATIALES MÉTIER (SÉANCE 5) — GÉOAI INONDATION CASABLANCA
-- Auteur : Siham Bouzagrar
-- Base   : geoai_casablanca
-- Schéma : geoai (SRID 26191)
-- =============================================================================

SET search_path = geoai, public;

-- =============================================================================
-- REQUÊTE 1 : EXPOSITION DU BÂTI AUX CRUES (ZONE TAMPON 150m DES OUEDS)
-- Objectif : Compter et mesurer la surface bâtie inondable selon les 3 classes
--            de vulnérabilité à moins de 150 mètres d'un oued.
-- =============================================================================

EXPLAIN ANALYZE
SELECT 
    b.classe_bati_3cas,
    COUNT(b.id) AS nb_batiments_exposes,
    ROUND(SUM(b.surface_m2)::numeric, 2) AS surface_totale_m2,
    ROUND(AVG(b.hauteur_estimee_m)::numeric, 1) AS hauteur_moyenne_m
FROM geoai.bati b
JOIN geoai.oued o
    ON ST_DWithin(b.geom, o.geom, 150)
GROUP BY b.classe_bati_3cas
ORDER BY nb_batiments_exposes DESC;

-- Résultat obtenu :
-- 1. 3_GrandComplexe_>=500m2 : 439 bâtiments exposés (1 281 430 m²)
-- 2. 2_Collectif_150_500m2   : 278 bâtiments exposés (83 076 m²)
-- 3. 1_Individuel_<150m2     : 143 bâtiments exposés (14 763 m²)
-- Total : 860 bâtiments directement menacés à moins de 150 m d'un oued.
-- Plan : Utilisation de l'Index Scan GIST sur sidx_bati_geom (Temps : ~320 ms).


-- =============================================================================
-- REQUÊTE 2 : ACCESSIBILITÉ DES SECOURS SUR LE BÂTI INDIVIDUEL CRITIQUE (KNN)
-- Objectif : Calculer la distance au secours le plus proche pour l'habitat individuel
--            vulnérable (<150 m²) en utilisant l'opérateur KNN (<->) et détecter
--            ceux isolés à plus de 1 000 m.
-- =============================================================================

EXPLAIN ANALYZE
SELECT 
    b.id,
    b.name,
    b.surface_m2,
    ROUND(secours.dist::numeric, 1) AS distance_secours_m
FROM (
    SELECT id, name, surface_m2, geom 
    FROM geoai.bati 
    WHERE classe_bati_3cas = '1_Individuel_<150m2'
    LIMIT 200
) b
CROSS JOIN LATERAL (
    SELECT ST_Distance(b.geom, c.geom) AS dist
    FROM geoai.caserne c
    ORDER BY b.geom <-> c.geom
    LIMIT 1
) secours
WHERE secours.dist > 1000
ORDER BY distance_secours_m DESC
LIMIT 10;

-- Plan : Utilisation de l'index spatial GIST via KNN (sidx_caserne_geom).
-- Temps d'exécution : ~33 ms !


-- =============================================================================
-- REQUÊTE 3 : AGRÉGATION SPATIALE MULTI-CRITÈRES POUR LA MAILLE D'ANALYSE
-- Objectif : Calculer pour chaque cellule de la grille (maille) la densité de bâti,
--            le nombre de bâtiments et la proximité hydrographique (AHP & ML).
-- =============================================================================

EXPLAIN ANALYZE
SELECT 
    m.id AS id_maille,
    COALESCE(SUM(b.surface_m2), 0) AS surface_batie_m2,
    COUNT(DISTINCT b.id) AS nb_batiments,
    COALESCE(ROUND(MIN(ST_Distance(m.geom, o.geom))::numeric, 1), 9999) AS distance_min_oued_m
FROM (SELECT * FROM geoai.maille LIMIT 50) m
LEFT JOIN geoai.bati b
    ON ST_Intersects(m.geom, b.geom)
LEFT JOIN geoai.oued o
    ON ST_DWithin(m.geom, o.geom, 2000)
GROUP BY m.id;

-- Plan : Double index scan GIST (sidx_oued_geom et sidx_bati_geom).
-- Temps d'exécution : ~3.5 ms !
