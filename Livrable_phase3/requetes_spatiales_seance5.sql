-- =============================================================================
-- Projet : GeoAI Inondation Casablanca — Séance 5
-- =============================================================================

-- =========================================================================
-- REQUÊTE 1
-- Mailles à très haut risque (classe 4-5) situées à moins de 200 m d'un oued
-- Métier : identifier les zones prioritaires d'alerte précoce
-- Utilise : score_risque, maille, cours_eau — jointure spatiale ST_DWithin
-- =========================================================================

-- Plan d'exécution (vérification des index GIST et de l'estimation des lignes)
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT
    m.id                        AS maille_id,
    m.geom,
    s.valeur                    AS score_ahp,
    s.classe                    AS classe_risque,
    MIN(ST_Distance(m.geom, ce.geom))::NUMERIC(10,2) AS dist_oued_m,
    ce.nom                      AS nom_oued_proche,
    ce.fclass                   AS type_oued
FROM score_risque s
JOIN maille m       ON m.id = s.maille_id
JOIN cours_eau ce   ON ST_DWithin(m.geom, ce.geom, 200)   -- 200 m en mètres (EPSG:26191)
WHERE s.classe >= 4
GROUP BY m.id, m.geom, s.valeur, s.classe, ce.nom, ce.fclass
ORDER BY s.valeur DESC, dist_oued_m ASC;


-- Requête seule (pour usage direct)
SELECT
    m.id                        AS maille_id,
    s.valeur                    AS score_ahp,
    s.classe                    AS classe_risque,
    MIN(ST_Distance(m.geom, ce.geom))::NUMERIC(10,2) AS dist_oued_m,
    ce.nom                      AS nom_oued_proche,
    ce.fclass                   AS type_oued
FROM score_risque s
JOIN maille m       ON m.id = s.maille_id
JOIN cours_eau ce   ON ST_DWithin(m.geom, ce.geom, 200)
WHERE s.classe >= 4
GROUP BY m.id, m.geom, s.valeur, s.classe, ce.nom, ce.fclass
ORDER BY s.valeur DESC, dist_oued_m ASC;


-- =========================================================================
-- REQUÊTE 2
-- Équipements sensibles (poids élevé) dans des mailles à risque > 0.6
-- Métier : cartographier les équipements vulnérables pour la gestion de crise
-- Utilise : equipement_poi, maille, score_risque — ST_Within (point dans polygone)
-- =========================================================================

EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT
    ep.fid                      AS equipement_id,
    ep.name                     AS nom_equipement,
    ep.categorie,
    ep.poids,
    ep.geom                     AS position,
    m.id                        AS maille_id,
    s.valeur                    AS score_ahp,
    s.classe                    AS classe_risque,
    c.nom                       AS commune
FROM equipement_poi ep
JOIN maille m       ON ST_Within(ep.geom, m.geom)
JOIN score_risque s ON s.maille_id = m.id
JOIN commune c      ON c.id = m.commune_id
WHERE ep.poids >= 3            -- équipements de forte criticité
  AND s.valeur > 0.6
ORDER BY ep.poids DESC, s.valeur DESC;


-- Requête seule
SELECT
    ep.fid                      AS equipement_id,
    ep.name                     AS nom_equipement,
    ep.categorie,
    ep.poids,
    s.valeur                    AS score_ahp,
    s.classe                    AS classe_risque,
    c.nom                       AS commune
FROM equipement_poi ep
JOIN maille m       ON ST_Within(ep.geom, m.geom)
JOIN score_risque s ON s.maille_id = m.id
JOIN commune c      ON c.id = m.commune_id
WHERE ep.poids >= 3
  AND s.valeur > 0.6
ORDER BY ep.poids DESC, s.valeur DESC;


-- =========================================================================
-- REQUÊTE 3
-- Surface de bâti exposé par commune (mailles classe ≥ 3)
-- + densité de population HCP pour priorisation
-- Métier : estimer la population et le bâti à risque par commune 
-- Utilise : commune, maille, score_risque, bati — ST_Intersection + ST_Area
-- =========================================================================

EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT
    c.id                        AS commune_id,
    c.nom                       AS commune,
    c.densite_hab_km2,
    COUNT(DISTINCT m.id)        AS nb_mailles_risque,
    ROUND(SUM(s.valeur) / COUNT(m.id), 4)   AS score_moyen,
    MAX(s.classe)               AS classe_max,
    -- Surface de bâti intersectant les mailles à risque (en m²)
    ROUND(
        COALESCE(SUM(
            ST_Area(ST_Intersection(b.geom, m.geom))
        ), 0)::NUMERIC, 2
    )                           AS bati_expose_m2,
    -- Population estimée exposée (densité * surface mailles à risque)
    ROUND(
        (c.densite_hab_km2 * SUM(ST_Area(m.geom)) / 1e6)::NUMERIC, 0
    )                           AS pop_exposee_estimee
FROM commune c
JOIN maille m       ON m.commune_id = c.id
JOIN score_risque s ON s.maille_id = m.id
LEFT JOIN bati b    ON ST_Intersects(b.geom, m.geom)
WHERE s.classe >= 3            -- risque moyen à très élevé
GROUP BY c.id, c.nom, c.densite_hab_km2
ORDER BY score_moyen DESC, bati_expose_m2 DESC;


-- Requête seule 
SELECT
    c.id                        AS commune_id,
    c.nom                       AS commune,
    c.densite_hab_km2,
    COUNT(DISTINCT m.id)        AS nb_mailles_risque,
    ROUND(SUM(s.valeur) / COUNT(m.id), 4)   AS score_moyen,
    MAX(s.classe)               AS classe_max,
    ROUND(
        COALESCE(SUM(ST_Area(ST_Intersection(b.geom, m.geom))), 0)::NUMERIC, 2
    )                           AS bati_expose_m2,
    ROUND(
        (c.densite_hab_km2 * SUM(ST_Area(m.geom)) / 1e6)::NUMERIC, 0
    )                           AS pop_exposee_estimee
FROM commune c
JOIN maille m       ON m.commune_id = c.id
JOIN score_risque s ON s.maille_id = m.id
LEFT JOIN bati b    ON ST_Intersects(b.geom, m.geom)
WHERE s.classe >= 3
GROUP BY c.id, c.nom, c.densite_hab_km2
ORDER BY score_moyen DESC, bati_expose_m2 DESC;


-- =========================================================================
-- NOTES SUR LES PLANS D'EXECUTION (attendus après EXPLAIN ANALYZE)
-- =========================================================================
/*
  REQUÊTE 1 — Mailles proches des oueds à haut risque
  ─────────────────────────────────────────────────────
  Nœuds attendus :
    - Index Scan sur score_risque (idx_score_classe) → filtre classe >= 4
    - Nested Loop → Index Scan sur maille (idx_maille_geom) via FK
    - Index Scan sur cours_eau (idx_cours_eau_geom) → ST_DWithin utilise GIST bbox
  Signe de bonne indexation : « Bitmap Heap Scan » ou « Index Scan using idx_maille_geom »
  Si « Seq Scan » sur cours_eau ou maille → vérifier que les index GIST existent.

  REQUÊTE 2 — Équipements vulnérables
  ─────────────────────────────────────────────────────
  Nœuds attendus :
    - Index Scan sur equipement_poi (idx_equip_geom) pour ST_Within bbox
    - Hash Join sur score_risque → filtre valeur > 0.6
  Attention : ST_Within exact (après filtre bbox GIST) reste en « Recheck Cond ».

  REQUÊTE 3 — Bâti exposé par commune
  ─────────────────────────────────────────────────────
  ST_Intersection + ST_Area = opération coûteuse.
  Attendu : Seq Scan sur bati si beaucoup d'intersections, ou Bitmap Heap via GIST.
  Optimisation possible : matérialiser la jointure maille-bati dans une table intermédiaire.
  Signe de problème : temps > 10 s → envisager un index BRIN sur maille.id
  ou une vue matérialisée « bati_par_maille ».
*/
