
# Sources de données brutes

**Projet :** Analyse de la susceptibilité aux inondations, de la vulnérabilité et de l'accessibilité des secours dans le Grand Casablanca  

**Système de coordonnées cible :** EPSG:26191 — Nord Maroc

---

## 1. Défi spatial et objectifs

**Question centrale :** Quelles zones du Grand Casablanca sont les plus susceptibles d'être inondées, quel est leur niveau de vulnérabilité et où se situent les services de secours accessibles ?

Le projet comprend trois analyses complémentaires :

- **Susceptibilité aux inondations :** identifier les zones présentant des caractéristiques physiques favorables aux inondations, à partir du relief, de la pente, de l'hydrographie et de l'occupation du sol.
- **Vulnérabilité :** croiser la susceptibilité avec l'exposition des bâtiments, des infrastructures, des équipements sensibles et de la population, lorsque les données sont disponibles, puis classer les secteurs en cinq niveaux.
- **Accessibilité des secours :** localiser les services de secours et analyser les itinéraires accessibles par le réseau routier, en tenant compte des tronçons potentiellement affectés.


---

## 2. OpenStreetMap — Extrait Geofabrik

| Élément | Détail |
|---|---|
| Source | [Geofabrik — Maroc](https://download.geofabrik.de/africa/morocco-latest-free.shp.zip) |
| Date de téléchargement | 20/10/2026 |
| Format | Archive ZIP contenant des Shapefiles thématiques |
| Licence | ODbL 1.0 — OpenStreetMap |
| CRS d'origine | EPSG:4326  |
| CRS cible | EPSG:26191 |
| Emprise | Maroc, puis extraction du Grand Casablanca |
| Couches exploitées | Routes, bâtiments, occupation du sol et points d'intérêt, selon les couches disponibles |
| Acquisition | Téléchargement et extraction automatisés avec `requests` et `zipfile` |

### Utilisation dans le projet

- Calcul de la densité des bâtiments et analyse des enjeux exposés.
- Caractérisation de l'occupation du sol urbain.
- Analyse de la proximité des routes et des infrastructures.
- Localisation des établissements utiles aux opérations de secours, sous réserve de vérifier les données disponibles.

---

## 3. Hydrographie — CartoMaroc

| Élément | Détail |
|---|---|
| Source | [Archive hydrographique CartoMaroc](https://drive.google.com/file/d/1w0md7nxYZzoyOhy364yMrdVsUiDpaJ-W) |
| Format original | Archive RAR |
| CRS d'origine | À vérifier pour chaque couche |
| CRS cible | EPSG:26191 |
| Emprise | Maroc, puis extraction du Grand Casablanca |
| Contenu | Oueds, lacs et dayas, barrages, bassins versants et nappes, selon les couches présentes |
| Acquisition | Téléchargement avec `gdown`, puis extraction automatisée |

### Utilisation dans le projet

- Calcul de la distance aux cours d'eau.
- Caractérisation du contexte hydrographique.
- Analyse de la proximité des oueds et des zones de drainage.
- Construction de variables explicatives pour la classification de la susceptibilité.

---

## 4. Modèle numérique de terrain — Grand Casablanca, 30 m

| Élément | Détail |
|---|---|
| Source | [Modèle numérique de terrain — Google Drive](https://drive.google.com/file/d/15qpvrKivrA5oO6AtYLPgZVen9tUmij6w) |
| Format | GeoTIFF |
| Résolution annoncée | 30 m |
| CRS d'origine | EPSG:4326  |
| CRS cible | EPSG:26191 |
| Emprise | Grand Casablanca |
| Acquisition | Téléchargement automatisé avec `gdown` |

### Utilisation dans le projet

- Calcul de l'altitude et de la pente.
- Identification des zones basses.
- Calcul éventuel de l'accumulation du ruissellement et d'autres indicateurs hydrologiques dérivés du relief.
- Contribution à la construction des variables utilisées pour la classification non supervisée.

**Limite :** une résolution de 30 m convient à une première analyse régionale, mais peut ne pas représenter les détails fins du drainage urbain.

---

## 5. Données démographiques — Haut-Commissariat au Plan (HCP)

| Élément | Détail |
|---|---|
| Organisme producteur | Haut-Commissariat au Plan du Maroc |
| Site officiel | [https://www.hcp.ma/](https://www.hcp.ma/) |
| Données recherchées | Population et indicateurs démographiques du RGPH 2024, selon disponibilité |
| Format |  Excel |
| Licence | Open source |
| Emprise | Grand Casablanca |


### Utilisation dans le projet

- Analyse de la population potentiellement exposée.
- Caractérisation de la vulnérabilité démographique.
- Contribution à la classification des secteurs en cinq niveaux de vulnérabilité.

**Précaution :** si les données sont disponibles uniquement à l'échelle communale, elles ne permettent pas de déterminer directement la population exposée dans chaque cellule de 30 m. L'échelle des données doit être documentée.

---

## 6. Variables envisagées pour les analyses

| Analyse | Variables ou données | Source |
|---|---|---|
| Susceptibilité | Altitude | MNT |
| Susceptibilité | Pente | MNT |
| Susceptibilité | Distance aux cours d'eau | CartoMaroc / OSM |
| Susceptibilité | Accumulation du ruissellement | Dérivée du MNT préparé |
| Susceptibilité | Occupation du sol | OSM, selon disponibilité |
| Vulnérabilité | Bâtiments et infrastructures exposés | OSM |
| Vulnérabilité | Population et indicateurs démographiques | HCP, selon disponibilité |
| Accessibilité | Réseau routier | OSM |
| Accessibilité | Hôpitaux et casernes de pompiers | OSM et autres sources vérifiées |

### Méthode de classification

La classification non supervisée pourra être réalisée avec K-means après :

1. Harmonisation de la grille spatiale et des systèmes de coordonnées.
2. Calcul des variables explicatives.
3. Traitement des valeurs manquantes et invalides.
4. Standardisation des variables.
5. Comparaison de plusieurs nombres de groupes.
6. Interprétation des groupes et attribution éventuelle de niveaux de susceptibilité.

Les numéros de groupes produits par l'algorithme ne représentent pas automatiquement les niveaux faible, moyen ou élevé.

La vulnérabilité sera analysée séparément à partir de la susceptibilité et des données d'exposition. L'accessibilité des secours fera l'objet d'une analyse de réseau.

---

## 7. Organisation des fichiers

```text
projet_inondations_casablanca/
├── donnees_brutes/
│   ├── osm/
│   ├── hydro/
│   │   ├── hydro.rar
│   │   └── extracted/
│   ├── dem/
│   │   └── DEM_Grand_Casablanca_30m.tif
│   ├── hcp/
│   └── routes/
├── script/
└── sources.md
```

---

## 8. Notes de reproductibilité

- Les scripts Python automatisent les téléchargements et l'organisation des fichiers lorsque cela est possible.
- Les fichiers originaux sont conservés dans `donnees_brutes/`.
- Le CRS réel de chaque couche est vérifié avant toute reprojection.
- Les noms des fichiers, les tailles et les empreintes SHA-256 sont conservés lorsque possible.


---

