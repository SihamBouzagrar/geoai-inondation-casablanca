# GÉODATA APPLIQUÉE
## Document 1er Jet

# Évaluation de la vulnérabilité aux inondations et planification des secours dans la region Casablanca-Settat

**Zone d'étude :** Region Casablanca Settat
**SCR cible :** EPSG:26191 (Merchich / Nord Maroc)

---

## 1. Défi spatial et objectifs opérationnels

> **Question centrale :** Quelles zones du Grand Casablanca sont les plus susceptibles d'être inondées, quel est leur niveau de vulnérabilité, et où se situent les services de secours accessibles ?

Le projet repose sur trois volets :

| # | Volet | Intitulé | Objectif |
|---|-------|----------|----------|
| 1 | 🌊 **Prédiction** | Aléa | Modéliser le ruissellement à partir de la géomorphologie et de la topographie, afin d'identifier précisément où l'eau stagne et déborde. Cartographie de la susceptibilité par clustering non supervisé (K-Means / GMM). |
| 2 | 🏢 **Classification** | Vulnérabilité | Croiser l'aléa avec les enjeux exposés (bâti dense, voirie, population RGPH 2024) pour hiérarchiser le degré de sévérité par secteur. |
| 3 | 🚒 **Localisation** | Secours | Cartographier les casernes de la Protection Civile et modéliser des itinéraires d'intervention résilients, évitant les axes inondables. |

---

## 2. Utilisateurs cibles et besoins métiers

- **Protection Civile et services d'urgence** : identifier les poches d'intervention prioritaires, prépositionner le matériel d'exhaure (pompes) et sécuriser les itinéraires d'évacuation praticables.
- **Agence Urbaine de Casablanca (AUC) et communes** : disposer d'un zonage d'aide à la décision pour encadrer la constructibilité dans les cuvettes et localiser les sites potentiels de bassins de rétention en amont (axes d'écoulement déduits du MNT).
- **Gestionnaires de voirie et Casa Transports** : repérer les coupures critiques du réseau routier et des lignes de transport en site propre (tramway) lors des crues torrentielles.

---

## 3. Inventaire des données brutes

Le pipeline repose sur **quatre sources ouvertes**, acquises par flux automatisés.

| Source | Fournisseur | Format / SCR | Variables extraites | Usage et contrôles | Lien d'accès |
|--------|-------------|--------------|---------------------|--------------------|--------------|
| **MNT (DEM 30 m)** | CartoMaroc / ESA | GeoTIFF / EPSG:26191 | Altitude, pente, direction et accumulation des flux, TWI, HAND, cuvettes, réseau de drainage dérivé | Base du modèle physique de ruissellement ; contrôle des NoData | [Google Drive](https://drive.google.com/file/d/15qpvrKivrA5oO6AtYLPgZVen9tUmij6w) |
| **Bâti & Oueds & infrastructures** | OSM (Geofabrik) | Shapefiles / EPSG:26191 | Emprises bâties, zones d'activités, équipements sensibles (écoles, hôpitaux) | Taux d'imperméabilisation et identification des enjeux exposés | [Geofabrik Maroc](https://download.geofabrik.de/africa/morocco-latest-free.shp.zip) |
| **Réseau routier** | OpenStreetMap (Overpass) | GeoJSON / EPSG:26191 | Voirie hiérarchisée, autoroutes, artères ; casernes (`amenity=fire_station`) | Graphe d'accessibilité des secours et coupures des axes en crue | [Overpass Turbo](https://overpass-turbo.eu/) |
| **Démographie** | HCP (RGPH 2024) | Excel (.xlsx) / tabulaire | Population légale, densité communale | Qualification de la vulnérabilité socio-économique par secteur urbain | [hcp.ma](https://www.hcp.ma/) |

**Harmonisation géodésique.** Toutes les couches sont reprojetées dans le SCR métrique officiel **EPSG:26191** pour garantir la superposition topologique et la précision métrique des distances et des surfaces.

---

## 4. Démarche méthodologique en 6 phases

1. **Acquisition et traçabilité** : téléchargement automatisé par scripts Python (API Overpass, Geofabrik, Google Drive API), avec catalogage des licences et métadonnées dans `SOURCES.md`.
2. **Prétraitement et géodatabase** : reprojection uniforme en EPSG:26191, découpage sur le bassin d'étude, correction topologique (MNT : remplissage des dépressions ; vecteurs : géométries valides), injection dans PostgreSQL/PostGIS avec index spatiaux GiST.
3. **Ingénierie des variables (*feature engineering*)** : découpage en mailles régulières (ou statistiques zonales) et calcul des indices : pente, TWI, HAND, accumulation des flux, `dist_drain`, profondeur des cuvettes, densité urbaine (taux de bâti).
4. **Modélisation Geo-AI hybride (Prédiction / Aléa)** : classification de susceptibilité non supervisée (K-Means / Fuzzy C-Means), interprétation des clusters en niveaux d'aléa (faible, modéré, élevé, critique). *Validation externe optionnelle* : comparaison avec des emprises d'inondation observées (par exemple Sentinel-1 du 12/01/2021, rappel spatial et ROC-AUC), hors pipeline de données principal.
5. **Vulnérabilité et logistique des secours (Classification / Localisation)** : croisement de l'aléa avec le bâti dense, les équipements sensibles, la voirie et la densité de population RGPH 2024 pour produire un indice de risque par secteur ; localisation des casernes OSM ; calcul des chemins d'accès optimaux (Dijkstra / A\*) sur le graphe routier résilient et délimitation des zones couvertes par temps de trajet.
6. **Contrôle qualité et valorisation** : vérification de la cohérence spatiale, cartographies décisionnelles sous QGIS, scripts documentés pour la reproductibilité.

---

## 5. Risques méthodologiques et limites identifiées

1. **Résolution altimétrique (30 m)** : le MNT lisse les trottoirs, fossés et micro-ouvrages d'assainissement.
   *Atténuation :* croisement avec les dépressions fermées (*sink fill*) et l'indice HAND.

2. **Fiabilité du graphe routier sous submersion** : les itinéraires théoriques peuvent être faussés par des radiers inondés.
   *Atténuation :* exclusion dynamique des tronçons classés en aléa « Critique ».
3. **Granularité de la démographie HCP** : les données sont communales, donc plus grossières que les mailles de calcul.
   *Atténuation :* désagrégation proportionnelle à la surface bâtie OSM (cartographie dasymétrique).

---

## 6. Livrables attendus

- Carte de **susceptibilité aux inondations** (aléa, 4 classes).
- Carte de **vulnérabilité / risque** par secteur.
- Carte des **casernes** et des **zones d'intervention** (isochrones, itinéraires résilients).
- Géodatabase PostGIS, scripts Python, `SOURCES.md` et rapport méthodologique.