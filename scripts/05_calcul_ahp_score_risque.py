#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
=============================================================================
PROJET : GeoAI - Vulnérabilité aux Inondations Urbaines, Grand Casablanca
MODULE : 05_calcul_ahp_score_risque.py
AUTEURS : Siham Bouzagrar & Khawla Kadiri
DATE : Novembre 2026
SCR CIBLE : EPSG:26191 (Merchich / Nord Maroc)
=============================================================================
Conforme au Schéma Conceptuel (MCD) 'schema_conceptuel_inondation.drawio' :
  - CalculAHP : Résolution spectrale de Saaty (vecteur propre, λmax, CI, CR < 0.10)
  - CritereAHP : 12 variables normalisées (sens 'cout' vs 'benefice')
  - ComparaisonPaire : Matrice réciproque (i < j, échelle 1-9)
  - ScoreRisque : Combinaison linéaire WLC (valeur ∈ [0, 1]) et 5 classes fixes
  - ModeleClustering : Export des entrées pondérées (variables normalisées × √poids)
  - PrioriteCommune : Synthèse par commune et indice de priorité
=============================================================================
"""

import os
import sys
import time
from datetime import datetime
from pathlib import Path
import json

import numpy as np
import pandas as pd
from scipy import linalg
from scipy.stats import spearmanr
import pyogrio

# Forcer l'encodage UTF-8 pour la console Windows
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

# -----------------------------------------------------------------------------
# 1. Configuration des Chemins
# -----------------------------------------------------------------------------
ROOT = Path(__file__).resolve().parent.parent if "__file__" in locals() else Path.cwd()
if ROOT.name == "scripts":
    ROOT = ROOT.parent

FICHIER_INPUT_CSV = ROOT / "input" / "mailles_100m_normalisees.csv"
FICHIER_MAILLES_GPKG = ROOT / "donnees_traitees" / "mailles" / "mailles_100m.gpkg"
FICHIER_COMMUNES_GPKG = ROOT / "donnees_traitees" / "casablanca_settat_clean" / "communes_casablanca_settat_clean.gpkg"

DOSSIER_SORTIE = ROOT / "donnees_traitees" / "scores"
DOSSIER_SORTIE.mkdir(parents=True, exist_ok=True)

FICHIER_SCORE_PARQUET = DOSSIER_SORTIE / "score_risque_100m.parquet"
FICHIER_SCORE_CSV = DOSSIER_SORTIE / "score_risque_100m.csv"
FICHIER_CLUSTERING_INPUT = DOSSIER_SORTIE / "entrees_clustering_100m.parquet"
FICHIER_METADATA_AHP = DOSSIER_SORTIE / "calcul_ahp_metadonnees.json"
FICHIER_PRIORITE_COMMUNES = DOSSIER_SORTIE / "priorite_communes.csv"

# -----------------------------------------------------------------------------
# 2. Table des 12 Critères et Définition de la Matrice de Saaty
# -----------------------------------------------------------------------------
# Ordre officiel des 12 critères
CRITERES_DEFS = [
    {"variable": "hand_moy",         "sens": "cout",     "dim": "Alea",    "target_w": 0.160},
    {"variable": "pente_moy",        "sens": "cout",     "dim": "Alea",    "target_w": 0.120},
    {"variable": "depression_moy",   "sens": "benefice", "dim": "Alea",    "target_w": 0.080},
    {"variable": "distance_oued",    "sens": "cout",     "dim": "Alea",    "target_w": 0.070},
    {"variable": "twi_moy",          "sens": "benefice", "dim": "Alea",    "target_w": 0.045},
    {"variable": "flux_max_log",     "sens": "benefice", "dim": "Alea",    "target_w": 0.040},
    {"variable": "ruissel_moy",      "sens": "benefice", "dim": "Alea",    "target_w": 0.035},
    {"variable": "indice_equip",     "sens": "benefice", "dim": "Enjeux",  "target_w": 0.140},
    {"variable": "densite_bati",     "sens": "benefice", "dim": "Enjeux",  "target_w": 0.100},
    {"variable": "densite_routes",   "sens": "benefice", "dim": "Enjeux",  "target_w": 0.060},
    {"variable": "pct_impermeable",  "sens": "benefice", "dim": "Enjeux",  "target_w": 0.040},
    {"variable": "distance_secours", "sens": "benefice", "dim": "Secours", "target_w": 0.110},
]

# Indice Aléatoire de Cohérence de Saaty (Random Index RI)
SAATY_RI = {
    1: 0.00, 2: 0.00, 3: 0.58, 4: 0.90, 5: 1.12,
    6: 1.24, 7: 1.32, 8: 1.41, 9: 1.45, 10: 1.49,
    11: 1.51, 12: 1.54, 13: 1.56, 14: 1.57, 15: 1.59
}

SAATY_SCALE = [1/9, 1/8, 1/7, 1/6, 1/5, 1/4, 1/3, 1/2, 1, 2, 3, 4, 5, 6, 7, 8, 9]

def closest_saaty(ratio: float) -> float:
    """Arrondit un ratio à la valeur discrète de l'échelle de Saaty [1/9 .. 9]."""
    return min(SAATY_SCALE, key=lambda x: abs(x - ratio))


class CalculAHP:
    """Classe implémentant le modèle AHP de Saaty conforme au MCD."""

    def __init__(self, scenario: str = "baseline"):
        self.scenario = scenario
        self.date_calcul = datetime.now().isoformat()
        self.criteres = CRITERES_DEFS
        self.n = len(self.criteres)
        self.variables = [c["variable"] for c in self.criteres]
        
        # Construction de la matrice de Saaty A (n x n)
        self.matrice_A = np.ones((self.n, self.n), dtype=np.float64)
        self.comparaisons_paires = []
        
        target_weights = np.array([c["target_w"] for c in self.criteres], dtype=np.float64)
        target_weights /= target_weights.sum()

        # Remplissage des paires (i < j)
        for i in range(self.n):
            for j in range(i + 1, self.n):
                val_saaty = closest_saaty(target_weights[i] / target_weights[j])
                self.matrice_A[i, j] = val_saaty
                self.matrice_A[j, i] = 1.0 / val_saaty
                self.comparaisons_paires.append({
                    "critere_i": i,
                    "critere_j": j,
                    "var_i": self.variables[i],
                    "var_j": self.variables[j],
                    "valeur_saaty": val_saaty
                })

        # Calcul spectral
        self.lambda_max = 0.0
        self.indice_coherence = 0.0
        self.ratio_coherence = 0.0
        self.poids = np.zeros(self.n, dtype=np.float64)
        self.calculer_poids()
        self.verifier_coherence()

    def calculer_poids(self):
        """Calcule le vecteur propre principal associé à la valeur propre maximale."""
        eigvals, eigvecs = linalg.eig(self.matrice_A)
        max_idx = np.argmax(np.real(eigvals))
        self.lambda_max = float(np.real(eigvals[max_idx]))
        
        # Vecteur propre principal normalisé (somme = 1)
        w = np.real(eigvecs[:, max_idx])
        w = w / np.sum(w)
        self.poids = w.astype(np.float64)

    def verifier_coherence(self):
        """Calcule l'indice de cohérence (CI) et le ratio de cohérence (CR)."""
        self.indice_coherence = float((self.lambda_max - self.n) / (self.n - 1))
        ri = SAATY_RI.get(self.n, 1.54)
        self.ratio_coherence = float(self.indice_coherence / ri)
        
        if self.ratio_coherence >= 0.10:
            print(f"[ATTENTION] CR = {self.ratio_coherence:.4f} >= 0.10 (Matrice incohérente)")
        else:
            print(f"[OK] Cohérence validée : λmax = {self.lambda_max:.4f}, CI = {self.indice_coherence:.4f}, CR = {self.ratio_coherence:.4f} ({self.ratio_coherence*100:.2f}%) < 10%")

    def get_dict_poids(self) -> dict:
        return {var: float(w) for var, w in zip(self.variables, self.poids)}


# -----------------------------------------------------------------------------
# 3. Pipeline Principal d'Exécution
# -----------------------------------------------------------------------------
def executer_calcul_ahp():
    print("=" * 80)
    print("   GÉOAI INONDATION GRAND CASABLANCA — CALCUL DU SCORE DE RISQUE AHP")
    print("   Conforme au MCD 'schema_conceptuel_inondation.drawio'")
    print("=" * 80)

    # 1. Vérification du fichier d'entrée
    if not FICHIER_INPUT_CSV.exists():
        raise FileNotFoundError(f"Fichier d'entrée introuvable : {FICHIER_INPUT_CSV}")

    print(f"\n[1/6] Lecture des données normalisées : {FICHIER_INPUT_CSV.name}...")
    t0 = time.time()
    # Chargement rapide avec le moteur PyArrow
    df = pd.read_csv(FICHIER_INPUT_CSV, engine="pyarrow")
    print(f"      -> {len(df):,} mailles chargées en {time.time() - t0:.2f} s.")
    print(f"      -> Colonnes disponibles ({len(df.columns)}) : {list(df.columns)}")

    # 2. Instanciation du modèle AHP (Scénario Baseline)
    print("\n[2/6] Résolution mathématique du modèle AHP (Scénario Baseline)...")
    ahp = CalculAHP(scenario="baseline")
    dict_poids = ahp.get_dict_poids()

    print("\n--- Poids AHP retenus par variable ---")
    for crit in CRITERES_DEFS:
        var = crit["variable"]
        w = dict_poids[var]
        w_ml = np.sqrt(w)
        print(f"  * {var:<18} [{crit['dim']:<7} | {crit['sens']:<8}] : Poids = {w:.4f} ({w*100:5.2f}%)  |  √Poids (ML) = {w_ml:.4f}")

    # 3. Calcul Vectorisé du Score de Risque Continu [0, 1]
    print("\n[3/6] Calcul vectoriel de ScoreRisque.valeur (Combinaison Linéaire Pondérée)...")
    t1 = time.time()
    
    # Matrice X des 12 variables alignées
    colonnes_vars = ahp.variables
    for c in colonnes_vars:
        if c not in df.columns:
            raise KeyError(f"Variable manquante dans le CSV : {c}")

    X = df[colonnes_vars].to_numpy(dtype=np.float32)
    w_vec = ahp.poids.astype(np.float32)

    # Produit matriciel vectorisé : Score = X · w
    score_continu = np.dot(X, w_vec)
    score_continu = np.clip(score_continu, 0.0, 1.0)

    # Discrétisation en 5 classes fixes selon le MCD (ScoreRisque.classe)
    # 1: Très Faible [0, 0.2[ | 2: Faible [0.2, 0.4[ | 3: Moyen [0.4, 0.6[ | 4: Élevé [0.6, 0.8[ | 5: Très Élevé [0.8, 1.0]
    bins = [0.0, 0.20, 0.40, 0.60, 0.80, 1.00001]
    classes = pd.cut(score_continu, bins=bins, labels=[1, 2, 3, 4, 5], right=False).astype(np.int8)

    print(f"      -> Calcul achevé pour {len(score_continu):,} mailles en {time.time() - t1:.2f} s.")

    # Distribution des classes
    print("\n--- Distribution des 5 classes de risque d'inondation ---")
    noms_classes = {
        1: "1. Très Faible [0.00 - 0.20[",
        2: "2. Faible      [0.20 - 0.40[",
        3: "3. Modéré      [0.40 - 0.60[",
        4: "4. Élevé       [0.60 - 0.80[",
        5: "5. Très Élevé  [0.80 - 1.00]"
    }
    dist_classes = pd.Series(classes).value_counts().sort_index()
    for cl_id, count in dist_classes.items():
        pct = (count / len(score_continu)) * 100
        print(f"  {noms_classes[cl_id]:<30} : {count:10,} mailles ({pct:6.2f}%)")

    # 4. Préparation des Entrées pour le Clustering IA (K-Means / GMM)
    print("\n[4/6] Génération des entrées pondérées pour l'IA (variables × √poids)...")
    # Selon le MCD : "ModeleClustering : entrées = variables normalisées × √poids"
    w_sqrt = np.sqrt(w_vec)
    X_clustering = X * w_sqrt
    df_clustering = pd.DataFrame(X_clustering, columns=colonnes_vars)
    df_clustering.insert(0, "id", df["id"].values)

    df_clustering.to_parquet(FICHIER_CLUSTERING_INPUT, index=False)
    print(f"      -> Entrées clustering enregistrées : {FICHIER_CLUSTERING_INPUT.name} ({FICHIER_CLUSTERING_INPUT.stat().st_size / 1e6:.1f} Mo)")

    # 5. Export des Tables ScoreRisque (Parquet & CSV)
    print("\n[5/6] Export des résultats de ScoreRisque...")
    df_score = pd.DataFrame({
        "maille_id": df["id"].values,
        "score_risque": score_continu,
        "classe_risque": classes
    })

    df_score.to_parquet(FICHIER_SCORE_PARQUET, index=False)
    print(f"      -> Parquet : {FICHIER_SCORE_PARQUET.name} ({FICHIER_SCORE_PARQUET.stat().st_size / 1e6:.1f} Mo)")
    
    # Export d'un échantillon CSV ou complet
    print(f"      -> Export CSV : {FICHIER_SCORE_CSV.name}...")
    df_score.to_csv(FICHIER_SCORE_CSV, index=False)
    print(f"      -> CSV terminé ({FICHIER_SCORE_CSV.stat().st_size / 1e6:.1f} Mo).")

    # Sauvegarde des métadonnées du calcul (CalculAHP, CritereAHP, ComparaisonPaire)
    metadata = {
        "scenario": ahp.scenario,
        "date_calcul": ahp.date_calcul,
        "lambda_max": ahp.lambda_max,
        "indice_coherence": ahp.indice_coherence,
        "ratio_coherence": ahp.ratio_coherence,
        "n_criteres": ahp.n,
        "criteres": [
            {
                "id": idx + 1,
                "variable": c["variable"],
                "dimension": c["dim"],
                "sens": c["sens"],
                "poids": float(ahp.poids[idx]),
                "poids_ml_sqrt": float(w_sqrt[idx])
            }
            for idx, c in enumerate(CRITERES_DEFS)
        ],
        "comparaisons_paires": ahp.comparaisons_paires
    }
    with open(FICHIER_METADATA_AHP, "w", encoding="utf-8") as f:
        json.dump(metadata, f, indent=2, ensure_ascii=False)
    print(f"      -> Métadonnées AHP exportées : {FICHIER_METADATA_AHP.name}")

    # 6. Priorisation par Commune (Table MCD : PrioriteCommune)
    print("\n[6/6] Calcul de PrioriteCommune (Agrégation par Commune)...")
    if FICHIER_MAILLES_GPKG.exists() and FICHIER_COMMUNES_GPKG.exists():
        try:
            print("      -> Jointure spatiale avec commune_id depuis mailles_100m.gpkg...")
            df_communes_mailles = pyogrio.read_dataframe(
                FICHIER_MAILLES_GPKG, columns=["id", "commune_id"], read_geometry=False
            )
            df_synth = df_score.merge(df_communes_mailles, left_on="maille_id", right_on="id", how="inner")
            
            # Ajout de densite_bati pour le calcul du bâti exposé
            df_synth["densite_bati"] = df["densite_bati"].values

            # Lecture des métadonnées communales
            df_communes_meta = pyogrio.read_dataframe(
                FICHIER_COMMUNES_GPKG, columns=["id", "nom", "surface_km2"], read_geometry=False
            )

            # Agrégation selon le MCD
            # pct_zones_elevees = mailles de classes 4-5 ÷ mailles de la commune
            # bati_expose_m2 = Σ (densite_bati × surface maille [10 000 m²]) sur mailles 4-5
            agg_communes = []
            for c_id, group in df_synth.groupby("commune_id"):
                tot_mailles = len(group)
                classes_4_5 = group[group["classe_risque"].isin([4, 5])]
                pct_elevees = len(classes_4_5) / tot_mailles if tot_mailles > 0 else 0.0
                score_moy = float(group["score_risque"].mean())
                score_max = float(group["score_risque"].max())
                bati_exp_m2 = float((classes_4_5["densite_bati"] * 10000.0).sum())

                agg_communes.append({
                    "commune_id": c_id,
                    "total_mailles": tot_mailles,
                    "nb_mailles_elevees": len(classes_4_5),
                    "pct_zones_elevees": pct_elevees,
                    "score_moyen": score_moy,
                    "score_max": score_max,
                    "bati_expose_m2": bati_exp_m2
                })

            df_prio = pd.DataFrame(agg_communes)
            df_prio = df_prio.merge(df_communes_meta, left_on="commune_id", right_on="id", how="left")

            # Normalisation du score moyen pour indice_priorite
            sm_min, sm_max = df_prio["score_moyen"].min(), df_prio["score_moyen"].max()
            df_prio["score_moyen_norm"] = (df_prio["score_moyen"] - sm_min) / (sm_max - sm_min) if sm_max > sm_min else 0.0

            # Indice de priorité (MCD : 0.7 × score_moyen normalisé + 0.3 × composante exposition)
            df_prio["indice_priorite"] = 0.7 * df_prio["score_moyen_norm"] + 0.3 * df_prio["pct_zones_elevees"]
            df_prio["rang_priorite"] = df_prio["indice_priorite"].rank(ascending=False, method="min").astype(int)
            df_prio = df_prio.sort_values(by="rang_priorite")

            df_prio.to_csv(FICHIER_PRIORITE_COMMUNES, index=False)
            print(f"      -> PrioriteCommune exportée : {FICHIER_PRIORITE_COMMUNES.name}")
            print("\n--- TOP 10 des Communes les plus vulnérables (Grand Casablanca) ---")
            top10 = df_prio[["rang_priorite", "nom", "score_moyen", "pct_zones_elevees", "bati_expose_m2"]].head(10)
            print(top10.to_string(index=False))

        except Exception as e:
            print(f"      [AVERTISSEMENT] Agrégation communale non finalisée : {e}")
    else:
        print("      [INFO] Couches de communes ou de mailles manquantes pour la synthèse communale.")

    print("\n" + "=" * 80)
    print("   CALCUL DU MODÈLE AHP TERMINÉ AVEC SUCCÈS !")
    print(f"   Scores générés sous : {DOSSIER_SORTIE}")
    print("=" * 80)


if __name__ == "__main__":
    executer_calcul_ahp()
