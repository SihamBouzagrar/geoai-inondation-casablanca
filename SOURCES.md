# Sources de données brutes

**Defit spatial : Quelles zones du Grand Casablanca sont les plus susceptibles d'être inondées , quel est leur niveau de vulnérabilité , et où se situent les zones de secours accessibles  ?**

**Système de coordonnées cible :** EPSG:26191 — Nord Maroc

## Objectif du projet

Le projet vise à identifier les secteurs du Grand Casablanca présentant une susceptibilité élevée aux inondations, à évaluer leur vulnérabilité et à localiser les services de secours accessibles.

Ces trois objectifs correspondent à des analyses complémentaires :

- **Susceptibilité :** estimer où le terrain est le plus prédisposé aux inondations, à partir du relief, des pentes, du réseau hydrographique et de l'occupation du sol.
- **Vulnérabilité :**  croiser la susceptibilité avec l'exposition des bâtiments, du réseau routier et ferré, des équipements sensibles (et de la population, si les données le permettent), puis classer les secteurs en cinq niveaux.
- **Accessibilité des secours :**  identifier les sites situés hors des zones les plus vulnérables, puis vérifier par analyse du réseau routier, tronçons inondés exclus, qu'ils sont accessibles et proches des services de secours (hôpitaux, casernes de pompiers).


## 1. OpenStreetMap — Extrait Geofabrik

| Élément                | Détail                                                                                                                               |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| URL                    | [https://download.geofabrik.de/africa/morocco-latest-free.shp.zip](https://download.geofabrik.de/africa/morocco-latest-free.shp.zip) |
                                                                                                                          |
| Format                 | Archive ZIP contenant des Shapefiles thématiques                                                                                     |
| Licence                | ODbL 1.0 — OpenStreetMap                                                                                                             |
| CRS d’origine          | EPSG:4326 - WGS 84                                                                                   |
| CRS cible              | EPSG:26191                                                                                                                           |
| Emprise                | Maroc, puis extraction de la zone d’étude du Grand Casablanca                                                                        |
| Couches exploitées     | Routes, bâtiments, occupation du sol, points d’intérêt                    |
| Acquisition            | Téléchargement et extraction automatisés avec `requests` et `zipfile`                                                                |

**Utilisation dans le projet :** 

## 2. Hydrographie — CartoMaroc

| Élément                  | Détail                                                                                                                                 |
| ------------------------ | -------------------------------------------------------------------------------------------------------------------------------------- |
| URL                      | [https://drive.google.com/file/d/1w0md7nxYZzoyOhy364yMrdVsUiDpaJ-W](https://drive.google.com/file/d/1w0md7nxYZzoyOhy364yMrdVsUiDpaJ-W) |
| Date de téléchargement   | 21/10/2026                                                                                                                             |
| Format original          | Archive RAR                                                                                                                            |
                                           |
| CRS d’origine            | À vérifier dans les métadonnées de chaque couche                                                                                       |
| CRS cible                | EPSG:4326 - WGS 84                                                                                                                          |
| Emprise                  | Maroc, avec extraction du Grand Casablanca                                                                                             |
| Contenu                  | Oueds, lacs et dayas, barrages, bassins versants et nappes, selon les couches effectivement présentes                                  |
| Acquisition              | Téléchargement avec `gdown`, puis extraction automatisée                                                                               |

**Utilisation dans le projet :** caractérisation de la proximité des cours d’eau, analyse du contexte hydrographique et identification des secteurs potentiellement exposés aux débordements.

## 3. Modèle numérique de terrain — Grand Casablanca, 30 m

| Élément                  | Détail                                                                                                                                 |
| ------------------------ | -------------------------------------------------------------------------------------------------------------------------------------- |
| URL                      | [https://drive.google.com/file/d/15qpvrKivrA5oO6AtYLPgZVen9tUmij6w](https://drive.google.com/file/d/15qpvrKivrA5oO6AtYLPgZVen9tUmij6w) |
| Date de téléchargement   | 21/10/2026                                                                                                                             |
| Format                   | GeoTIFF                                                                                                                                |
| Résolution annoncée      | 30 m                                                                                                                                   |
                                                                                                
| CRS d’origine            | EPSG:4326 - WGS 84raster                                                                                               |
| CRS cible                | EPSG:26191                                                                                                                             |
| Emprise                  | Grand Casablanca                                                                                                                       |
| Acquisition              | Téléchargement automatisé avec `gdown`                                                                                                 |

**Utilisation dans le projet :** calcul de variables topographiques telles que l’altitude, la pente et, selon la qualité du modèle, des indicateurs dérivés du relief utiles à l’analyse de la susceptibilité aux inondations.

## Notes de reproductibilité

- Les scripts Python assurent le téléchargement et l’organisation des données.
- Les fichiers originaux sont conservés dans `donnees_brutes/`.
- Les données transformées, reprojetées ou dérivées sont stockées séparément dans `donnees_traitees/`.
- Le CRS réel de chaque couche est vérifié avant toute reprojection.
- Les métadonnées de téléchargement, les tailles des fichiers et les empreintes SHA-256 sont conservées lorsque possible.
- Les dates de téléchargement sont distinguées des dates de publication ou de mise à jour des sources.
- Les données manquantes, les limites de résolution et les restrictions de licence sont documentées.  je nai pas compris ce qu il faut prq n est pas suffisant deja on va faire classifictaionnon superie