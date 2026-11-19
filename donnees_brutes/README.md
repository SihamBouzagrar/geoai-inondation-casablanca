# Données brutes – Projet Inondation Grand Casablanca

Ce dossier contient les données sources, conservées telles quelles (aucune modification).
Les sources, licences et dates de téléchargement sont détaillées dans `SOURCES.md`.

## Contenu du dossier

```text
donnees_brutes/
├── README.md                         
│
├── osm/                               # Shapefiles OpenStreetMap (Geofabrik, Maroc)
│                                      # NON versionné (voir ci-dessous)
│
├── routes/                            # Réseau routier (OpenStreetMap via Overpass)
│   ├── osm_routes_brut.json           # Réponse brute de l'API Overpass
│   └── routes_casablanca.geojson      # Routes reconstruites en GeoJSON (EPSG:4326)
│
├── hcp/                               # Haut-Commissariat au Plan
│   └── rgph_2024/                     # Données du RGPH 2024 (fichiers Excel)
│
└── dem/                               # Modèle numérique de terrain
    └── DEM_Grand_Casablanca_30m.tif   # GeoTIFF, résolution 30 m
```

## Données non versionnées

Le dossier `osm/` **n'est pas importé dans le dépôt** : l'extrait Geofabrik du Maroc dépasse la limite de taille autorisée. Il est exclu du suivi Git (ajouter `donnees_brutes/osm/` au `.gitignore`).

Pour le reconstituer en local :

```bash
python scripts/01_import_brut.py
```

Le script télécharge l'archive Geofabrik et extrait les Shapefiles dans `donnees_brutes/osm/` récupère-le via le lien indiqué dans `SOURCES.md` si le dossier est vide.

## Rôle des sources

| Dossier | Source | Rôle dans le projet |
|---|---|---|
| `osm/` | OpenStreetMap (Geofabrik) | Bâtiments, équipements (POI), occupation du sol, cours d'eau et limites administratives |
| `routes/` | OpenStreetMap (Overpass) | Réseau routier pour l'accessibilité des secours et le repérage des tronçons exposés |
| `hcp/` | Haut-Commissariat au Plan | Population et indicateurs démographiques pour la vulnérabilité humaine |
| `dem/` | MNT 30 m | Altitude, pente et indicateurs hydrologiques |

## Remarques

- Les fichiers de ce dossier ne sont jamais modifiés. Les couches découpées sont dans `donnees_decoupes/` et les couches nettoyées dans `donnees_traitees/`.

```
