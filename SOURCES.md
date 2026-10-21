# Sources de données brutes  
**Projet : Prédiction de la susceptibilité d’inondation – Grand Casablanca**  
**Date de documentation** : 21 octobre 2026  
**CRS cible** : EPSG:26191 (Nord Maroc)

---

## 1. OpenStreetMap – Extrait Geofabrik

| Élément | Détail |
|---------|--------|
| **URL** | https://download.geofabrik.de/africa/morocco-latest-free.shp.zip |
| **Date de téléchargement** | 20/10/2026 |
| **Format** | Shapefiles thématiques (.shp) |
| **Licence** | ODbL 1.0 (Open Data Commons Open Database License) |
| **CRS d’origine** | EPSG:4326 |
| **CRS final** | EPSG:26191 |
| **Emprise** | Maroc (extrait filtré ensuite sur Grand Casablanca) |
| **Contenu utilisé** | routes, bâtiments, landuse, waterways, water, pois, admin, places |
| **Script** | Téléchargement + extraction automatisés via `requests` + `zipfile` |

---

## 2. Hydrographie CartoMaroc

| Élément | Détail |
|---------|--------|
| **URL** | https://drive.google.com/file/d/1w0md7nxYZzoyOhy364yMrdVsUiDpaJ-W |
| **Date de téléchargement** | 21/10/2026 |
| **Format original** | .rar |
| **Licence** | Usage pédagogique (CartoMaroc) |
| **CRS d’origine** | À vérifier (probablement EPSG:4326 ou 26191) |
| **CRS final** | EPSG:26191 |
| **Emprise** | Maroc / focus Grand Casablanca |
| **Contenu** | Oueds (normal + détaillé), Lacs & Dayas, Barrages, Bassins versants, Nappes |
| **Script** | Téléchargement automatisé via `gdown` + extraction WinRAR |

---

## 3. DEM Grand Casablanca 30 m

| Élément | Détail |
|---------|--------|
| **URL** | https://drive.google.com/file/d/15qpvrKivrA5oO6AtYLPgZVen9tUmij6w |
| **Date de téléchargement** | 21/10/2026 |
| **Format** | GeoTIFF |
| **Résolution** | 30 mètres |
| **Licence** | Usage pédagogique |
| **CRS d’origine** | À documenter après ouverture |
| **CRS final** | EPSG:26191 |
| **Emprise** | Grand Casablanca |
| **Script** | Téléchargement automatisé via `gdown` |

---

## Notes de reproductibilité

- Tous les téléchargements sont automatisés dans le script Python.
- Aucune manipulation manuelle en « clic-clic » n’est nécessaire après la première exécution.
- Les fichiers bruts sont versionnés dans le dossier `donnees_brutes/`.