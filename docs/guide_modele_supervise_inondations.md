# Guide d'Implémentation du Modèle Supervisé pour la Susceptibilité aux Inondations

**Projet :** GeoIA Inondation Casablanca  
**Zone d'étude :** Grand Casablanca / Casablanca-Settat  
**Objectif :** Méthodologie complète pour collecter les zones inondées historiques (2021 et 2010), préparer les données, et entraîner un modèle de Machine Learning supervisé (Random Forest, XGBoost).

---

## Sommaire

1. [Principe fondamental du modèle supervisé](#1-principe-fondamental-du-modèle-supervisé)
2. [Identification des zones inondées historiques (Vérité Terrain)](#2-identification-des-zones-inondées-historiques-vérité-terrain)
   - [Événement de Janvier 2021 (Sentinel-1 SAR & Télédétection Radar)](#a-événement-de-janvier-2021--le-radar-sentinel-1-sar)
   - [Événement de Novembre 2010 (Landsat, MODIS & Données Historiques)](#b-événement-de-novembre-2010--landsat-dfo-et-archives-locales)
3. [Constitution du Dataset d'entraînement (Points 0 et 1)](#3-constitution-du-dataset-dentraînement)
   - [Génération des pseudo-absences (Points non inondés = 0)](#stratégie-déchantillonnage-des-non-inondations-y--0)
   - [Extraction des variables prédictives (X)](#extraction-des-variables-prédictives-x)
4. [Entraînement et Algorithmes recommandés](#4-entraînement-et-algorithmes-recommandés)
   - [Pourquoi Random Forest et XGBoost ?](#pourquoi-random-forest-et-xgboost-)
   - [Précaution cruciale : La validation croisée spatiale (Spatial K-Fold)](#précaution-cruciale--la-validation-croisée-spatiale-spatial-k-fold)
5. [Évaluation des performances](#5-évaluation-des-performances)
6. [Génération de la carte prédictive de susceptibilité](#6-génération-de-la-carte-prédictive-de-susceptibilité)
7. [Scripts pratiques et code réutilisable](#7-scripts-pratiques-et-code-réutilisable)

---

## 1. Principe fondamental du modèle supervisé

Contrairement à l'apprentissage non supervisé (qui regroupe les pixels par similarité de relief sans savoir s'ils inondent réellement), le **modèle supervisé** apprend la relation mathématique entre :

$$\hat{Y} = f(X_1, X_2, \dots, X_p)$$

* **$X$ (Variables explicatives / Covariables) :** Dérivées du MNT (altitude, pente, courbure, TWI), hydrographie (distance aux oueds), et OSM (bâti, routes, imperméabilité des sols). *Ces données sont déjà prévues dans votre projet.*
* **$Y$ (Variable cible / Vérité terrain) :**
  * $Y = 1$ : Secteur effectivement inondé lors d'un événement réel.
  * $Y = 0$ : Secteur non inondé lors du même événement.

---

## 2. Identification des zones inondées historiques (Vérité Terrain)

Pour entraîner un modèle, il est nécessaire de cartographier avec précision les inondations passées à Casablanca. Deux événements majeurs constituent la référence d'étalonnage :

### A. Événement de Janvier 2021 : Le Radar Sentinel-1 SAR

Entre le **5 et le 10 janvier 2021**, Casablanca a subi des pluies torrentielles exceptionnelles (> 100 mm en quelques jours), submergeant de nombreux quartiers (Sidi Bernoussi, Hay Sadri, Ain Sebaa, Moulay Rachid, Tit Mellil).

#### Pourquoi Sentinel-1 SAR est la meilleure méthode ?
* Les inondations s'accompagnent d'un ciel couvert (nuages denses). Les satellites optiques (Sentinel-2, Landsat) sont alors aveugles.
* Le capteur **SAR (Radar à synthèse d'ouverture)** de Sentinel-1 envoie des micro-ondes (bande C) qui traversent la couverture nuageuse, de jour comme de nuit.
* **Comportement physique de l'eau :** Une surface d'eau calme agit comme un miroir spéculaire et renvoie l'onde radar loin du capteur. L'eau apparaît donc en **noir (rétrodiffusion très faible, typiquement < -15 dB en polarisation VH/VV)**.

#### Procédure d'extraction avec Google Earth Engine (GEE)
1. **Sélectionner deux images Sentinel-1 GRD :**
   * *Image de référence (période sèche) :* 15 au 25 décembre 2020.
   * *Image de crue :* 6 au 10 janvier 2021.
2. **Filtrage et prétraitement :** Polarisation `VH` ou `VV`, mode `IW` (*Interferometric Wide Swath*).
3. **Calcul de la différence de rétrodiffusion :**
   $$\Delta \sigma^0 = \sigma^0_{\text{inondation}} - \sigma^0_{\text{référence}}$$
4. **Seuillage binaire :** Les pixels dont la chute de rétrodiffusion dépasse un seuil (ex: $\Delta \sigma^0 < -3.5 \text{ dB}$) et dont la pente est $< 5^\circ$ sont classés comme eau temporaire ($Y = 1$).
5. **Filtrage de l'eau permanente :** Exclure l'océan Atlantique et les barrages existants à l'aide de la couche hydrographique CartoMaroc.

---

### B. Événement de Novembre 2010 : Landsat, DFO et Archives Locales

Le **29 et 30 novembre 2010**, un déluge historique a frappé Casablanca (près de 180 mm en 24h, soit la moitié des précipitations annuelles), provoquant le débordement de l'Oued Bouskoura, l'inondation de l'autoroute urbaine et de multiples zones industrielles.

> [!WARNING]
> **Sentinel-1 n'existait pas en 2010** (Sentinel-1A a été lancé en avril 2014). Il faut donc employer des sources alternatives adaptées à cette époque.

#### 1. Satellites optiques d'archives (Landsat 5 & MODIS)
* **Landsat 5 TM :** Résolution 30 m (parfaitement alignée avec le MNT Copernicus 30 m). Si une scène dégagée est disponible juste après l'épisode (début décembre 2010), calculer le **MNDWI** (*Modified Normalized Difference Water Index*) :
  $$\text{MNDWI} = \frac{\text{Green} - \text{SWIR}}{\text{Green} + \text{SWIR}} = \frac{\text{Band 2} - \text{Band 5}}{\text{Band 2} + \text{Band 5}}$$
* **MODIS NRT Global Flood Product (Terra/Aqua) :** Résolution 250 m, passage bi-quotidien. Permet d'observer l'emprise des grands plans d'eau temporaires fin novembre 2010.

#### 2. Dartmouth Flood Observatory (DFO) & Global Flood Database
* Le **DFO (Université du Colorado)** archive mondialement les inondations depuis 1985.
* L'événement de Casablanca de novembre 2010 y est référencé avec un polygone d'emprise globale et les dates d'activation.

#### 3. Cartographie par géoréférencement des rapports locaux et médias
L'événement de 2010 a été exhaustivement documenté au sol. Vous pouvez créer une couche ponctuelle vectorielle en géoréférençant :
* Les rapports d'intervention de la **Protection Civile** et de la **Lydec** (points noirs d'engorgement).
* Les études de l'**Agence du Bassin Hydraulique du Bouregreg et de la Chaouia (ABHBC)** relatives au schéma de protection de Casablanca contre les crues de l'Oued Bouskoura.
* La presse d'époque (L'Économiste, Le Matin, Médias24) listant les carrefours, trémies, tunnels, et cités submergées (Sidi Moumen, Route d'El Jadida, Ain Sebaa, Lahraouiyine).

---

## 3. Constitution du Dataset d'entraînement

Pour un modèle binaire robuste, il faut un tableau structuré contenant des points d'inondation ($Y=1$) et des points de non-inondation ($Y=0$).

```text
+----------+------------+------------+----------+-------+--------+-----+-------+
| point_id | longitude  | latitude   | altitude | pente |  twi   | ... | flood |
+----------+------------+------------+----------+-------+--------+-----+-------+
|    1     | -7.589123  | 33.578412  |   42.5   |  1.2  | 11.45  | ... |   1   |
|    2     | -7.632145  | 33.512344  |  128.0   | 14.8  |  4.20  | ... |   0   |
+----------+------------+------------+----------+-------+--------+-----+-------+
```

### Stratégie d'échantillonnage des non-inondations ($Y = 0$)
Pour éviter de biaiser le modèle, les pseudo-absences doivent être sélectionnées scientifiquement :
1. Définir une zone d'exclusion autour des points d'inondation (buffer de sécurité de 200 à 500 m).
2. Échantillonner aléatoirement des points dans des zones à très faible probabilité physique d'inondation :
   * Pentes fortes ($> 10^\circ$)
   * Sommets et crêtes topographiques
   * Zones éloignées des talwegs et du réseau hydrographique
3. **Équilibrage :** Viser un ratio 1:1 (par exemple 1 500 points inondés pour 1 500 points non inondés).

### Extraction des variables prédictives ($X$)
À partir des coordonnées de chaque point, échantillonner les valeurs des rasters préparés à la résolution 30 m :
* **Topographie :** Altitude (MNT), Pente (Slope), Courbure (Curvature), Aspect.
* **Hydrologie :** TWI (*Topographic Wetness Index*), Distance aux oueds (CartoMaroc), Densité de drainage.
* **Anthropique & Sol :** Densité des bâtiments OSM, Distance au réseau routier principal, Indice d'imperméabilité des sols.

---

## 4. Entraînement et Algorithmes recommandés

### Pourquoi Random Forest et XGBoost ?
1. **Random Forest (Forêt d'arbres décisionnels) :**
   * Référence internationale en GeoIA et hydrologie spatiale.
   * Ne nécessite pas de normalisation stricte des variables.
   * Insensible aux valeurs extrêmes (*outliers*).
   * Fournit l'importance relative de chaque variable (*Feature Importance*), expliquant si c'est la pente, l'altitude ou le TWI qui gouverne les inondations à Casablanca.
2. **XGBoost / LightGBM :**
   * Algorithmes de Gradient Boosting extrêmement rapides et précis pour capturer des non-linéarités complexes en milieu urbain dense.

### Précaution cruciale : La validation croisée spatiale (Spatial K-Fold)
En données géographiques, les pixels proches se ressemblent (loi de Tobler : **autocorrélation spatiale**).
* Si vous effectuez un simple `train_test_split(random_state=42)` aléatoire, le modèle aura un score artificiellement élevé (> 98%) en "trichant", car il aura déjà vu des pixels voisins dans le jeu de test.
* **Solution :** Utiliser une **validation croisée par blocs spatiaux (Spatial K-Fold)** : la région de Casablanca est découpée en blocs géographiques (ex: 5 zones distinctes). Le modèle est entraîné sur 4 blocs et testé sur le 5ᵉ bloc totalement indépendant.

---

## 5. Évaluation des performances

Les métriques à calculer sur le jeu de test :
1. **ROC-AUC (Area Under the Receiver Operating Characteristic Curve) :**
   * $> 0.80$ : Bon modèle
   * $> 0.90$ : Excellent modèle
2. **Success Rate Curve (Courbe de taux de succès) :** Standard en cartographie des risques naturels.
3. **Matrice de confusion, F1-Score et Rappel (Recall) :** Le rappel sur la classe 1 est prioritaire (on préfère une fausse alerte plutôt que de manquer une zone inondée).

---

## 6. Génération de la carte prédictive de susceptibilité

Une fois le modèle validé :
1. Pour chaque pixel de la grille raster de Casablanca-Settat, extraire son vecteur de prédicteurs $X$.
2. Prédire la probabilité continue d'inondation à l'aide de `model.predict_proba(X)[:, 1]`.
3. Réécrire cette matrice sous forme de raster GeoTIFF (EPSG:26191) avec les mêmes dimensions et emprise que le MNT 30 m d'origine.
4. Classer la probabilité $[0, 1]$ en 5 classes de susceptibilité selon la méthode des seuils naturels (**Natural Breaks / Jenks**) :
   * $0.00 - 0.20$ : Susceptibilité Très Faible
   * $0.20 - 0.40$ : Susceptibilité Faible
   * $0.40 - 0.60$ : Susceptibilité Moyenne
   * $0.60 - 0.80$ : Susceptibilité Forte
   * $0.80 - 1.00$ : Susceptibilité Très Forte

---

## 7. Scripts pratiques et code réutilisable

### A. Script Google Earth Engine (Extraction Sentinel-1 pour Janvier 2021)

```javascript
// Définir la zone d'intérêt (BBOX Casablanca)
var casablanca = ee.Geometry.Rectangle([-7.80, 33.45, -7.35, 33.72]);

// Collection Sentinel-1 GRD
var s1 = ee.ImageCollection('COPERNICUS/S1_GRD')
  .filter(ee.Filter.eq('instrumentMode', 'IW'))
  .filter(ee.Filter.listContains('transmitterReceiverPolarisation', 'VH'))
  .filterBounds(casablanca);

// Image avant inondation (Décembre 2020)
var before = s1.filterDate('2020-12-15', '2020-12-30').select('VH').mosaic();

// Image pendant inondation (6 - 10 Janvier 2021)
var during = s1.filterDate('2021-01-06', '2021-01-11').select('VH').mosaic();

// Différence de rétrodiffusion
var diff = during.subtract(before);

// Masque inondation (chute significative de signal)
var flood = diff.lt(-3.0).and(during.lt(-15.0)).clip(casablanca);

Map.centerObject(casablanca, 11);
Map.addLayer(before, {min: -25, max: 0}, 'Avant (Déc 2020)');
Map.addLayer(during, {min: -25, max: 0}, 'Pendant (Jan 2021)');
Map.addLayer(flood.updateMask(flood), {palette: ['red']}, 'Zones Inondées Janvier 2021');
```

---

### B. Exemple de Pipeline Python (Scikit-Learn / Random Forest)

```python
import geopandas as gpd
import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import classification_report, roc_auc_score
from sklearn.model_selection import train_test_split

# 1. Charger les points labellisés (Y = 1 et Y = 0)
# Shapefile ou GeoPackage contenant les points et les variables extraites
gdf = gpd.read_file("donnees_traitees/echantillon_inondations.gpkg")

features = [
    "altitude",
    "pente",
    "twi",
    "dist_oued",
    "densite_bati",
    "dist_routes"
]
X = gdf[features].values
y = gdf["flood"].values  # 1 = inondé, 0 = non inondé

# 2. Séparation Apprentissage / Test
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.3, random_state=42, stratify=y
)

# 3. Entraînement du modèle Random Forest
rf = RandomForestClassifier(
    n_estimators=300,
    max_depth=15,
    min_samples_split=5,
    random_state=42,
    n_jobs=-1
)
rf.fit(X_train, y_train)

# 4. Évaluation
y_pred = rf.predict(X_test)
y_proba = rf.predict_proba(X_test)[:, 1]

print("ROC-AUC Score :", roc_auc_score(y_test, y_proba))
print("\nRapport de classification :")
print(classification_report(y_test, y_pred))

# 5. Importance des facteurs explicatifs
for nom, imp in zip(features, rf.feature_importances_):
    print(f"Facteur {nom:15s} : {imp * 100:.2f}%")
```

---

## 8. Synthèse

| Étape | Inondations 2010 | Inondations 2021 |
| :--- | :--- | :--- |
| **Période clé** | 29-30 Novembre 2010 | 5-10 Janvier 2021 |
| **Capteur satellite privilégié** | Landsat 5 TM (30 m) / MODIS | Sentinel-1 SAR (Radar 10 m) |
| **Sensibilité météo** | Sensible aux nuages (optique) | Totalement insensible aux nuages (radar) |
| **Compléments indispensables** | Rapports ABHBC, Lydec, archives presse | Points d'intervention Protection Civile, Lydec |
| **Exploitation ML** | Calibrage et benchmark historique | Cartographie précise de l'emprise ($Y=1$) |
