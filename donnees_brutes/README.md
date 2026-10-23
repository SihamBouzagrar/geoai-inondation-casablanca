# Données brutes – Projet Inondation Grand Casablanca

## Contenu du dossier

```text
donnees_brutes/
├── osm/                              # Données OpenStreetMap (Geofabrik)
│
├── routes/                           # Données routières
│   ├── routes_maroc.*                # Données routières brutes si source distincte
│   └── README.md                     # Source, date et description
│
├── hcp/                              # Données statistiques du Haut-Commissariat au Plan
│   ├── rgph_2024/                    # Données du RGPH 2024
│   
│   
│
├── hydro/
│   ├── hydro.rar           # Archive originale hydrographique
│   └── extracted/                    # Couches hydrographiques extraites
│
├── dem/
│   └── DEM_Grand_Casablanca_30m.tif  # Modèle numérique de terrain à 30 m

```

## Rôle des nouvelles sources

- **HCP** : données de population et indicateurs démographiques pour analyser la vulnérabilité humaine.
- **Routes** : réseau routier pour étudier l’accessibilité des zones touchées et des itinéraires de secours.
- **OSM** : autres objets géographiques utiles, notamment les bâtiments et les équipements, selon les couches disponibles.


python scripts/01_import_brut.py
```
