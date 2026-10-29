# Données traitées — GeoIA Inondation Casablanca

## 1. Présentation

Ce dossier contient les couches géospatiales après prétraitement des données **OpenStreetMap (OSM)**, du réseau routier extrait via **Overpass** et des données hydrographiques **CartoMaroc** pour le projet *GeoIA Inondation Casablanca*.

L’objectif est de disposer de données plus fiables et homogènes pour les prochaines étapes du projet : analyse spatiale, création du maillage, calcul des facteurs d’exposition et de vulnérabilité, puis cartographie des zones prioritaires.

## 2. Organisation du dossier

Les couches nettoyées sont enregistrées dans le sous-dossier :

```text
donnees_traitees/
└── casablanca_settat_clean/
    ├── bati_casablanca_settat_clean.gpkg
    ├── routes_casablanca_settat_clean.gpkg
    ├── occupation_sol_casablanca_settat_clean.gpkg
    ├── equipements_poi_casablanca_settat_clean.gpkg
    ├── infrastructures_secours_clean.gpkg
    ├── oued_detaille_casablanca_settat_clean.gpkg
    └── oued_principal_casablanca_settat_clean.gpkg
```

Les fichiers listés correspondent aux sorties prévues par le notebook de traitement. Un fichier peut être absent si sa couche source n’était pas disponible ou si la cellule correspondante n’a pas été exécutée.

## 3. Couches produites

| Fichier | Contenu |
|---|---|
| `bati_casablanca_settat_clean.gpkg` | Emprises des bâtiments OSM nettoyées, avec des attributs complétés et une typologie estimée du bâti. |
| `routes_casablanca_settat_clean.gpkg` | Réseau routier issu d’Overpass, nettoyé et reprojeté. |
| `occupation_sol_casablanca_settat_clean.gpkg` | Couche OSM d’occupation du sol. |
| `equipements_poi_casablanca_settat_clean.gpkg` | Points d’intérêt et équipements issus d’OSM. |
| `infrastructures_secours_clean.gpkg` | Couche de points issue des données OSM de trafic/infrastructures, selon les données sources disponibles. |
| `oued_detaille_casablanca_settat_clean.gpkg` | Réseau hydrographique détaillé CartoMaroc. |
| `oued_principal_casablanca_settat_clean.gpkg` | Réseau des oueds principaux CartoMaroc. |

## 4. Traitements réalisés

Le notebook `03_nettoyage_geometries.ipynb` met en œuvre les opérations suivantes, selon la couche :

- **Contrôle qualité** : diagnostic des valeurs manquantes, des géométries NULL ou vides et des géométries invalides.
- **Réparation géométrique** : utilisation de `make_valid` pour tenter de réparer les géométries invalides.
- **Suppression des anomalies** : retrait des géométries vides et des doublons géométriques stricts, selon les règles du script.
- **Contrôle du type géométrique** : conservation des géométries attendues pour chaque couche (points, lignes ou polygones).
- **Traitement des attributs du bâti** : remplacement des noms manquants par « Non renseigné », calcul de `surface_m2` et estimation de la classe du bâti lorsque les informations nécessaires sont disponibles.
- **Reprojection** : harmonisation des couches vers le système de coordonnées `EPSG:26191` (Merchich / Nord Maroc).
- **Export** : enregistrement des couches finales au format GeoPackage (`.gpkg`).

### Typologie estimée du bâti

Le traitement prévoit trois classes basées notamment sur la surface au sol et une hauteur estimée :

1. **Bâti individuel** : surface inférieure à 150 m² ; hauteur indicative d’environ 4,5 m.
2. **Bâti collectif** : surface comprise entre 150 et 500 m² ; hauteur indicative d’environ 12 m.
3. **Grands complexes** : surface supérieure ou égale à 500 m² ; hauteur indicative d’environ 10 m.

Ces classes sont des **estimations produites pour l’analyse du projet**. Elles ne constituent pas une mesure terrain de la hauteur ni, à elles seules, une validation de la vulnérabilité réelle d’un bâtiment.

## 5. Système de coordonnées

Le système cible déclaré dans le notebook est :

- **CRS :** `EPSG:26191`
- **Usage :** système projeté métrique permettant notamment de calculer des surfaces et des distances.

Vérifier le CRS de chaque couche dans QGIS avant de réaliser des analyses ou de les combiner avec d’autres sources.

## 6. Rapport de contrôle qualité

Le notebook produit un rapport CSV récapitulant, pour les couches traitées, des informations telles que :

- nombre d’entités initiales ;
- géométries invalides détectées ;
- géométries vides supprimées ;
- doublons géométriques supprimés ;
- nombre d’entités après nettoyage ;
- CRS initial et CRS final.

Le chemin configuré dans le notebook pour ce rapport est :

```text
donnees_decoupes/rapport_nettoyage_geometries.csv
```

Le rapport est donc enregistré dans `donnees_decoupes/`, et non directement dans `donnees_traitees/`.

## 7. Utilisation dans QGIS

1. Ouvrir QGIS.
2. Ajouter les fichiers `.gpkg` depuis `donnees_traitees/casablanca_settat_clean/`.
3. Vérifier le système de coordonnées et l’emprise des couches.
4. Examiner les attributs, notamment `surface_m2` et `classe_bati_3cas` pour le bâti.
5. Consulter `rapport_nettoyage_geometries.csv` pour vérifier le bilan du nettoyage.

## 8. Sources et traçabilité

- **OSM** : couches de bâtiments, occupation du sol, points d’intérêt et infrastructures.
- **Overpass** : réseau routier de Casablanca.
- **CartoMaroc** : couches hydrographiques des oueds.
- **Script de traitement** : `03_nettoyage_geometries.ipynb`.

Les données nettoyées restent dépendantes de la qualité, de la date et de la couverture des sources d’origine. Le nettoyage géométrique ne garantit pas que toutes les erreurs sémantiques ou les omissions des données sources ont été corrigées.

## 9. Remarque importante

Les couches préparées constituent une étape de prétraitement. Elles ne représentent pas, à elles seules, une carte prédictive des inondations. La prédiction et l’évaluation de la vulnérabilité nécessitent d’autres facteurs (par exemple relief, pente, précipitations, occupation du sol et exposition des enjeux), ainsi qu’une validation adaptée.
