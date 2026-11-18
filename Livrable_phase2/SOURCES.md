# Sources de données brutes

**Projet :** Susceptibilité aux inondations, vulnérabilité et accessibilité des secours dans le Grand Casablanca (région Casablanca-Settat)

---

## 1. Contexte et objectifs

**Question centrale :** quelles zones sont les plus susceptibles d'être inondées, quel est leur niveau de vulnérabilité, et où se trouvent les services de secours accessibles ?

Le projet repose sur trois analyses complémentaires :

| Analyse | Objectif | Données mobilisées |
|---|---|---|
| **Susceptibilité** | Repérer les zones physiquement favorables aux inondations | MNT (altitude, pente), cours d'eau OSM, occupation du sol OSM (coefficient de ruissellement par classe) |
| **Vulnérabilité** | Croiser la susceptibilité avec les enjeux exposés, puis classer les secteurs en cinq niveaux | Bâtiments (catégorisés et pondérés), POI sensibles, population HCP (si disponible) |
| **Accessibilité des secours** | Localiser les secours et analyser les itinéraires accessibles | Casernes et police (POI OSM), réseau routier Overpass, tronçons potentiellement exposés |

---

## 2. Vue d'ensemble des sources

| # | Source | Producteur | Format | Licence | Usage principal |
|---|---|---|---|---|---|
| 1 | Extrait OSM Maroc | Geofabrik / OpenStreetMap | Shapefiles → GeoPackage | ODbL 1.0 | Cours d'eau, bâti, occupation du sol, POI |
| 2 | Réseau routier | OpenStreetMap via Overpass | GeoJSON | ODbL 1.0 | Graphe routier, accessibilité |
| 3 | Modèle numérique de terrain | À documenter (fichier sur Google Drive) | GeoTIFF, 30 m | À documenter | Altitude, pente, indicateurs hydrologiques |
| 4 | Données démographiques RGPH 2024 | Haut-Commissariat au Plan (HCP) | Excel | À vérifier | Population exposée, vulnérabilité démographique |

**Systèmes de coordonnées :** toutes les sources sont fournies en EPSG:4326. Elles sont reprojetées en **EPSG:26191** (Merchich / Nord Maroc) pour les calculs de distances et de surfaces. Le CRS réel de chaque couche est vérifié avant toute reprojection.

---

## 3. OpenStreetMap — Extrait Geofabrik

| Élément | Détail |
|---|---|
| Source | [Geofabrik — Maroc](https://download.geofabrik.de/africa/morocco-latest-free.shp.zip) |
| Date de téléchargement | 20/10/2026 |
| Format d'origine | Archive ZIP de Shapefiles thématiques |
| Format de travail | GeoPackage (`*_casablanca_settat.gpkg`), après découpage |
| Licence | ODbL 1.0 — © contributeurs OpenStreetMap |
| CRS d'origine → cible | EPSG:4326 → EPSG:26191 |
| Emprise | Maroc, puis découpage à la limite de la région Casablanca-Settat |
| Acquisition | Automatisée (`requests`, `zipfile`) |

### 3.1 Couches exploitées

| Couche Geofabrik | Contenu | Rôle dans le projet |
|---|---|---|
| `gis_osm_waterways_free_1` | Cours d'eau | Distance aux cours d'eau, contexte hydrographique |
| `gis_osm_buildings_a_free_1` | Bâtiments | Densité du bâti, enjeux exposés |
| `gis_osm_landuse_a_free_1` | Occupation du sol | Surfaces imperméables et perméables, ruissellement |
| `gis_osm_pois_free_1` | Points d'intérêt | Équipements sensibles et services de secours |
| `gis_osm_adminareas_a_free_1` | Limites administratives | Limite de la région (`admin_level4`) pour le découpage |

Le réseau routier n'est pas tiré de cet extrait (voir section 4).

### 3.2 Traitements appliqués

**Cours d'eau**
- Seules les classes `river`, `stream`, `canal` et `drain` sont conservées.
- L'attribut `type_trace` distingue les tracés présumés naturels (`river`, `stream`) des tracés présumés artificiels (`canal`, `drain`).
- Le réseau est nodé aux confluences pour permettre les analyses de drainage.

**Bâtiments**
- Chaque bâtiment reçoit une **catégorie** et un **poids de vulnérabilité**.
- Ordre de décision : type OSM, puis reclassement par POI contenu dans le bâtiment, puis règle de surface pour les bâtiments non typés.
- Les bâtiments `abandoned`, `ruins` et `construction` sont exclus.

**Occupation du sol**
- Chaque classe reçoit une catégorie (imperméable, perméable, autre) et un **coefficient de ruissellement**.
- Les coefficients sont des hypothèses, à tester en analyse de sensibilité.

**Points d'intérêt**
- Les POI sont répartis en catégories : secours, santé, éducation, gouvernance, hébergement et rassemblement, commerce essentiel, infrastructure.
- Les services de secours sont extraits à part (`fire_station`, `police`).
- Si OSM ne contient aucune caserne de la Protection Civile, elles seront ajoutées manuellement et documentées.

---

## 4. Routes — OpenStreetMap via l'API Overpass

| Élément | Détail |
|---|---|
| Source | [Overpass API](https://overpass-turbo.eu/) |
| Date de téléchargement | À renseigner |
| Format | GeoJSON (un fichier par tuile en cache, un fichier fusionné) |
| CRS d'origine → cible | EPSG:4326 → EPSG:26191 |
| Emprise | Région Casablanca-Settat, rectangle `32.15, -9.10, 33.85, -6.70` (sud, ouest, nord, est) |
| Types de voies | `motorway`, `trunk`, `primary`, `secondary` |
| Licence | ODbL 1.0 — © contributeurs OpenStreetMap |

**Méthode d'acquisition :** l'emprise est découpée en 8 × 8 tuiles pour éviter les erreurs 502/504 du serveur Overpass. Chaque tuile réussie est mise en cache, puis toutes les tuiles sont fusionnées et dédupliquées par `osm_id`. Un relancement ne retélécharge que les tuiles manquantes.

**Fichiers produits :**
- `routes_grand_casablanca.geojson` : couche finale fusionnée.
- `tuiles_geojson/tuile_8x8_XX.geojson` : cache par tuile.

**Attributs conservés :** `osm_id`, `nom_rue`, `type_voie`, `surface`, `lanes`, `bridge`, `tunnel`.

**Usage :** construction du graphe routier pour l'accessibilité des secours et repérage des tronçons exposés aux inondations.

---

## 5. Modèle numérique de terrain (MNT)

| Élément | Détail |
|---|---|
| Source | [MNT — Google Drive](https://drive.google.com/file/d/15qpvrKivrA5oO6AtYLPgZVen9tUmij6w) |
| Producteur d'origine | À documenter |
| Format | GeoTIFF |
| Résolution annoncée | 30 m |
| CRS d'origine → cible | EPSG:4326 → EPSG:26191 (rééchantillonnage bilinéaire, 30 m) |
| Emprise | Grand Casablanca (à vérifier : doit couvrir toute la zone d'étude) |

**Usage :**
- Altitude, pente et identification des zones basses.
- Accumulation du ruissellement et autres indicateurs hydrologiques dérivés du relief.
- Construction des variables utilisées pour la classification non supervisée.

---

## 6. Données démographiques — HCP

| Élément | Détail |
|---|---|
| Organisme producteur | Haut-Commissariat au Plan du Maroc |
| Site officiel | [https://www.hcp.ma/](https://www.hcp.ma/) |
| Données recherchées | Population et indicateurs démographiques du RGPH 2024, selon disponibilité |
| Format | Excel |
| Licence | À vérifier (conditions de réutilisation à confirmer auprès du HCP) |
| Emprise | Grand Casablanca |

**Usage :**
- Analyse de la population potentiellement exposée.
- Caractérisation de la vulnérabilité démographique.
- Contribution à la classification des secteurs en cinq niveaux de vulnérabilité.

---

## 7. Variables envisagées

| Analyse | Variable | Source |
|---|---|---|
| Susceptibilité | Altitude | MNT |
| Susceptibilité | Pente | MNT |
| Susceptibilité | Accumulation du ruissellement | Dérivée du MNT |
| Susceptibilité | Distance aux cours d'eau | OSM (Geofabrik, waterways) |
| Susceptibilité | Occupation du sol | OSM (Geofabrik, landuse), selon disponibilité |
| Vulnérabilité | Bâtiments et infrastructures exposés | OSM (Geofabrik) |
| Vulnérabilité | Population et indicateurs démographiques | HCP, selon disponibilité |
| Accessibilité | Réseau routier | OSM (Overpass) |
| Accessibilité | Casernes de pompiers et police | OSM (Geofabrik, POI) |
| Accessibilité | Hôpitaux | OSM (Geofabrik, POI) et autres sources vérifiées |

---

## 8. Limites connues

- **Réseau routier :** seules les routes principales (motorway à secondary) sont extraites. La densité routière est sous-estimée en zone urbaine.
- **Occupation du sol :** OSM ne couvre pas tout le territoire. Les surfaces sans polygone ne sont pas classées.
- **Coefficients de ruissellement et poids de vulnérabilité :** ce sont des hypothèses, à justifier et à tester en sensibilité.
- **Secours :** la couche repose sur `fire_station` et `police`. Les casernes de la Protection Civile absentes d'OSM doivent être ajoutées manuellement.
- **Population :** les données HCP ne sont intégrées que si elles sont disponibles à l'échelle voulue.

---

## 9. Organisation des fichiers

```text
Geodata/
├── Livrable_phase1/
│   └── Document_1erJet.md
│
├── Livrable_phase2/
│
├── donnees_brutes/
│   ├── osm/                                    # Shapefiles Geofabrik
│   ├── dem/
│   │   └── DEM_Grand_Casablanca_30m.tif
│   ├── hcp/
│   │   └── [fichiers Excel HCP téléchargés]
│   └── routes/
│             
│
├── donnees_decoupes/
│   └── casablanca_settat/
│       ├── osm/
│       │   └── [couches OSM découpées .gpkg]
│       └── limite_casablanca_settat.gpkg
│
├── donnees_traitees/
│   └── casablanca_settat_clean/
│       ├── bati_casablanca_settat_clean.gpkg
│       ├── equipements_poi_casablanca_settat_clean.gpkg
│       ├── infrastructures_secours_clean.gpkg
│       ├── occupation_sol_casablanca_settat_clean.gpkg
│       ├── oued_detaille_casablanca_settat_clean.gpkg
│       └── oued_principal_casablanca_settat_clean.gpkg
│
├── scripts/
│   ├── 01_acquisition_donnees.ipynb
│   ├── 02_decoupage_donnees.ipynb
│   ├── 
│   ├──
│   └── 
│
└── SOURCES.md
```

---

## 10. Reproductibilité

- Les scripts Python automatisent les téléchargements et l'organisation des fichiers lorsque c'est possible.
- Les fichiers originaux sont conservés tels quels dans `donnees_brutes/`.
- Les couches découpées sur l’emprise de la zone d’étude sont conservées dans `donnees_decoupes/`.
- Les étapes de traçabilité (brut → traité) sont affichées à l'exécution des scripts de prétraitement.


