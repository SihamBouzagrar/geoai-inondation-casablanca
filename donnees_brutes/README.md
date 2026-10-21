# Données brutes – Projet Inondation Grand Casablanca

## Contenu du dossier

```text
donnees_brutes/
├── osm/                          # OpenStreetMap (Geofabrik)
├── source2/
│   ├── source2_donnees.rar       # Archive originale hydro
│   └── extracted/                # Couches hydrographiques extraites
├── dem/
│   └── DEM_Grand_Casablanca_30m.tif
└── processed/                    # Versions reprojetées EPSG:26191 (générées par le script)



//python 01_import_brut.py