
# Données decoupes — Casablanca-Settat

## 1. Présentation

Ce répertoire contient les données géographiques produites lors du prétraitement spatial du projet SIG consacré à l'analyse de la susceptibilité aux inondations dans la région Casablanca-Settat, au Maroc.

Les données sont générées à partir des sources originales stockées dans `donnees_brutes/`. Les fichiers sources sont conservés intacts afin de garantir la traçabilité et la reproductibilité des traitements.

## 2. Organisation du répertoire

```text
donnees_decoupes/
├── README.md
└── casablanca_settat/
    ├── osm/
    ├── hydrographie/
    
```

### 2.1. Données OpenStreetMap (OSM)

**Répertoire :** `casablanca_settat/osm/`

Contient les couches géographiques OpenStreetMap découpées selon la limite administrative de Casablanca-Settat.

Les couches disponibles peuvent notamment inclure :
- Bâtiments
- Occupation du sol
- Espaces naturels
- Hydrographie OSM
- Lieux et points d'intérêt

### 2.2. Données hydrographiques CartoMaroc

**Répertoire :** `casablanca_settat/hydrographie/`

Contient les couches issues de la source hydrographique CartoMaroc après découpage spatial.

Les couches traitées comprennent notamment :
- Cours d'eau (`Oued`)
- Cours d'eau détaillés (`Oued-Détaillé`)
- Bassins hydrographiques
- Lacs et dayas
- Barrages
- Nappes

La disponibilité de chaque couche dépend des données présentes dans la source originale.



## 3. Méthodologie de traitement

Le traitement spatial est organisé selon les étapes suivantes :

1. Identification de la limite administrative de la région Casablanca-Settat.
2. Vérification de la validité de la géométrie de la limite.
3. Découpage spatial des couches OSM.
4. Découpage spatial des couches hydrographiques CartoMaroc.
5. Export des résultats au format GeoPackage (`.gpkg`).
6. Vérification du nombre d'entités et des éventuelles erreurs de traitement.


Les données découpées sont destinées à être utilisées dans les analyses spatiales ultérieures et à être intégrées dans PostGIS.

## 4. Scripts et reproductibilité

Les traitements sont réalisés à l'aide des scripts et notebooks Python présents dans le répertoire `scripts/`.

Le workflow peut être reproduit en suivant l'ordre suivant :

1. Préparer les données sources conformément à `donnees_brutes/README.md`.
2. Installer les dépendances Python nécessaires, notamment GeoPandas et ses dépendances.
3. Exécuter le notebook d'acquisition des données si nécessaire.
4. Exécuter le notebook de découpage spatial.

Les chemins d'entrée et de sortie doivent correspondre à l'organisation locale du projet.

## 5. Formats de données

| Format | Utilisation |
|---|---|
| GeoPackage (`.gpkg`) | Stockage des couches géographiques découpées |
| CSV (`.csv`) | Rapports de traitement et bilans |
| GeoJSON (`.geojson`) | Échange de données géographiques, si nécessaire |

## 6. Gestion des données dans Git

Les fichiers géographiques volumineux générés pendant le traitement sont exclus du dépôt Git à l'aide du fichier `.gitignore`.

Le dépôt conserve principalement :
- La documentation des données
- Les scripts et notebooks de traitement
- Les fichiers de configuration nécessaires à la reproductibilité

Les fichiers de données traitées sont générés localement et peuvent être partagés séparément si nécessaire.

## 7. Étapes suivantes

Les données traitées serviront de base aux étapes suivantes du projet :

- Reprojection et harmonisation des systèmes de coordonnées
- Contrôle de la qualité géométrique et attributaire
- Préparation des variables spatiales liées à la susceptibilité aux inondations
- Intégration des couches validées dans PostGIS


---

**Zone d'étude :** Région Casablanca-Settat, Maroc  
**Format principal des données traitées :** GeoPackage (`.gpkg`)  
**CRS cible du projet :** EPSG:26191
