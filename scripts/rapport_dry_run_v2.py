#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Rapport DRY-RUN : audit géométrique et topologique avant nettoyage.
Projet GeoAI Inondation Casablanca.

- Mode rapport seul : AUCUN fichier n'est écrit ni modifié.
Usage :
       python rapport_dry_run_v2.py

    python rapport_dry_run.py
    python rapport_dry_run.py --racine D:\\projets\\geoai-inondation-casablanca
"""
import argparse
import os
import sys
from collections import Counter
from pathlib import Path

# Conflit PROJ / PostgreSQL fréquent sous Windows
if os.name == "nt":
    os.environ.pop("PROJ_LIB", None)
    os.environ.pop("PROJ_DATA", None)

if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

import numpy as np
import pandas as pd

try:
    import geopandas as gpd
    import shapely
    from shapely.geometry import MultiLineString, Point
except ImportError:
    print("[ERREUR] GeoPandas et Shapely (>= 2.0) sont nécessaires : pip install geopandas shapely")
    sys.exit(1)

CRS_CIBLE = "EPSG:26191"          # Merchich / Nord Maroc (mètres)
SEUIL_ANNEXE = 15                 # m² (même hypothèse que le prétraitement OSM)
SEUIL_GRAND = 2000                # m²
TOLERANCE_NODAGE = 1.0            # m : distance max pour une jonction en T non nodée
PARASITES = {"", "yes", "q", "type", "null", "none", "nan", "silc", "frequency"}


# =============================================================================
# OUTILS GÉNÉRAUX
# =============================================================================
def trouver_racine(arg_racine):
    if arg_racine:
        return Path(arg_racine).expanduser().resolve()
    env = os.environ.get("GEOAI_RACINE")
    if env:
        return Path(env).expanduser().resolve()

    departs = []
    try:
        departs.append(Path(__file__).resolve().parent)
    except NameError:
        pass
    departs.append(Path.cwd().resolve())

    for depart in departs:
        for candidat in [depart, *depart.parents]:
            if any((candidat / d).is_dir()
                   for d in ("donnees_decoupes", "donnees_traitees", "donnees_brutes")):
                return candidat
    return None


def chercher(racine, relatifs=(), alternatives=()):
    """Cherche un .gpkg : d'abord les chemins relatifs connus, puis par mots-clés dans
    donnees_decoupes/ et donnees_traitees/ (noms de fichiers légèrement différents d'une machine à l'autre)."""
    for rel in relatifs:
        p = racine / rel
        if p.exists():
            return p
    for mots in alternatives:
        for dossier in ("donnees_decoupes", "donnees_traitees"):
            base = racine / dossier
            if not base.is_dir():
                continue
            for p in sorted(base.rglob("*.gpkg")):
                nom = p.name.lower()
                if all(m in nom for m in mots):
                    return p
    return None


def union(gs):
    return gs.union_all() if hasattr(gs, "union_all") else gs.unary_union


def entete(titre):
    print("\n" + "=" * 105)
    print(titre)
    print("=" * 105)


def vers_cible(gdf):
    return gdf if gdf.crs.to_epsg() == 26191 else gdf.to_crs(CRS_CIBLE)


def charger_emprise(racine):
    p = chercher(racine,
                 ["donnees_decoupes/casablanca_settat/limite_casablanca_settat.gpkg"],
                 [("limite",)])
    if p is None:
        p = chercher(racine,
                     ["donnees_traitees/casablanca_settat_clean/communes_casablanca_settat_clean.gpkg"],
                     [("commune",)])
    if p is None:
        return None, None
    try:
        g = gpd.read_file(p)
        if g.crs is None:
            return None, p
        geom = union(vers_cible(g).geometry)
        shapely.prepare(geom)
        return geom, p
    except Exception:
        return None, p


# =============================================================================
# AUDIT GÉNÉRIQUE D'UNE COUCHE (en mémoire, rien n'est écrit)
# =============================================================================
def auditer_couche(racine, nom, relatifs, alternatives, emprise):
    rap = {"Couche": nom, "Fichier": "-", "Entités initiales": 0, "SCR initial": "-",
           "Vides/nulles": 0, "Invalides": 0, "Doublons stricts": 0, "Hors emprise": 0,
           "Entités après nettoyage": 0, "Statut": "Absent"}

    chemin = chercher(racine, relatifs, alternatives)
    if chemin is None:
        return rap, None
    rap["Fichier"] = chemin.name

    try:
        brut = gpd.read_file(chemin)
    except Exception as e:
        rap["Statut"] = f"Erreur lecture : {str(e)[:40]}"
        return rap, None

    rap["Entités initiales"] = len(brut)
    rap["SCR initial"] = str(brut.crs) if brut.crs else "Non défini"
    if len(brut) == 0:
        rap["Statut"] = "Vide"
        return rap, None
    if brut.crs is None:
        rap["Statut"] = "SCR absent (non audité)"
        return rap, None

    gdf = vers_cible(brut)

    vide = gdf.geometry.isna() | gdf.geometry.is_empty
    rap["Vides/nulles"] = int(vide.sum())
    g = gdf[~vide].copy()

    rap["Invalides"] = int((~g.geometry.is_valid).sum())

    # Doublon strict = géométrie ET attributs identiques (deux POI de même position
    # mais de types différents ne sont pas des doublons)
    tab = g.drop(columns="geometry").astype(str)
    tab["_geom"] = g.geometry.to_wkb(hex=True)
    doublon = tab.duplicated()
    rap["Doublons stricts"] = int(doublon.sum())

    if emprise is not None:
        dans = g.geometry.intersects(emprise)
        rap["Hors emprise"] = int((~dans).sum())
    else:
        dans = pd.Series(True, index=g.index)
        rap["Hors emprise"] = -1          # emprise non disponible

    rap["Entités après nettoyage"] = int((~doublon & dans).sum())
    rap["Statut"] = "Audité"
    return rap, g


# =============================================================================
# CAS 2 : WATERWAYS OSM — nodage et jonctions en T
# =============================================================================
def _extremites(lignes):
    """Compte le degré de chaque extrémité (coordonnées arrondies au cm)."""
    degre, proprietaire = Counter(), {}
    for i, l in enumerate(lignes):
        c = list(l.coords)
        for xy in (c[0], c[-1]):
            cle = (round(xy[0], 2), round(xy[1], 2))
            degre[cle] += 1
            proprietaire.setdefault(cle, i)
    return degre, proprietaire


def cas_waterways(racine):
    print("CAS B : « Waterways » OSM : continuité du réseau (nodage, jonctions en T)")
    print("-" * 105)
    chemin = chercher(racine, [], [("waterways",)])
    if chemin is None:
        print("  [ABSENT] Couche waterways introuvable : cas non calculé sur cette machine.")
        return
    gdf = gpd.read_file(chemin)
    if gdf.crs is None:
        print(f"  [ATTENTION] SCR absent dans {chemin.name} : cas non audité.")
        return
    g = vers_cible(gdf)
    g = g[g.geometry.notna() & ~g.geometry.is_empty]

    types = g.geom_type.value_counts().to_dict()
    non_lin = g[~g.geom_type.isin(["LineString", "MultiLineString"])]
    lignes = [p for geom in g[g.geom_type.isin(["LineString", "MultiLineString"])].geometry
              for p in shapely.get_parts(geom) if p.length > 0]

    degre, proprio = _extremites(lignes)
    dangles = [k for k, d in degre.items() if d == 1]

    arbre = shapely.STRtree(lignes)
    t_non_nodees = 0
    for cle in dangles:
        voisins = arbre.query(Point(cle).buffer(TOLERANCE_NODAGE), predicate="intersects")
        if any(int(i) != proprio[cle] for i in voisins):
            t_non_nodees += 1

    noded = shapely.get_parts(shapely.node(MultiLineString(lignes)))
    degre2, _ = _extremites(list(noded))
    dangles_apres = sum(1 for d in degre2.values() if d == 1)

    print(f"  Fichier                    : {chemin.name}")
    print(f"  Entités / types            : {len(g):,} {types}")
    print(f"  Géométries non linéaires   : {len(non_lin):,} (à écarter)")
    print(f"  Tronçons linéaires         : {len(lignes):,}")
    print(f"  Extrémités libres (dangles): {len(dangles):,}")
    print(f"  dont jonctions en T non nodées (< {TOLERANCE_NODAGE:.0f} m d'un autre tronçon) : {t_non_nodees:,}")
    print(f"  Après nodage simulé        : {len(noded):,} tronçons | {dangles_apres:,} extrémités libres")
    print("  Conséquence                : un écoulement ne traverse pas une jonction sans sommet commun")
    print("                               (continuité rompue pour la distance au réseau et les analyses de drainage).")
    print("  Correction (dry-run)       : purge des non-linéaires + shapely.node() (NON appliquée ici).")


# =============================================================================
# DIAGNOSTIC DU BÂTI
# =============================================================================
def diagnostic_bati(g):
    print(f"  Bâtiments analysés       : {len(g):,}")
    if "type" in g.columns:
        t = g["type"].astype("string").str.strip().str.lower()
        manquants = t.isna() | t.isin(PARASITES)
        print(f"  Champ 'type' manquant    : {manquants.mean():.1%} ({int(manquants.sum()):,} bâtiments)")
    else:
        print("  Champ 'type'             : absent de cette couche")

    surf = g.geometry.area
    print(f"  Emprise bâtie totale     : {surf.sum():,.0f} m² (~{surf.sum() / 1e6:.2f} km²)")
    print(f"  Annexes (< {SEUIL_ANNEXE} m²)         : {int((surf < SEUIL_ANNEXE).sum()):,}")
    print(f"  Standard ({SEUIL_ANNEXE}-{SEUIL_GRAND} m²)     : "
          f"{int(((surf >= SEUIL_ANNEXE) & (surf <= SEUIL_GRAND)).sum()):,}")
    print(f"  Grands (> {SEUIL_GRAND} m²)          : {int((surf > SEUIL_GRAND).sum()):,}")
    if "categorie" in g.columns:
        print("  Catégories (couche déjà prétraitée) :")
        print(g["categorie"].value_counts().to_string().replace("\n", "\n    "))


# =============================================================================
# AUDIT DU MNT
# =============================================================================
def audit_dem(racine):
    try:
        import rasterio
    except ImportError:
        print("  [IGNORÉ] rasterio non installé : audit du MNT non réalisé (pip install rasterio).")
        return
    dossier = racine / "donnees_brutes" / "dem"
    fichiers = sorted(dossier.glob("*.tif")) if dossier.is_dir() else []
    if not fichiers:
        print(f"  [ABSENT] Aucun .tif dans {dossier}. Audit du MNT non réalisé sur cette machine.")
        return

    with rasterio.open(fichiers[0]) as src:
        a = src.read(1, masked=True)
        res = src.res
        crs = src.crs
        h, w = a.shape

    lignes = [
        ("Fichier", fichiers[0].name),
        ("SCR", str(crs)),
        ("Résolution", f"{res[0]:.6g} x {res[1]:.6g} (unités du SCR)"),
        ("Dimensions", f"{w:,} x {h:,} pixels"),
        ("Pixels NoData", f"{int(a.size - a.count()):,}"),
        ("Altitudes négatives", f"{int((a < 0).sum()):,} pixels"),
        ("Plage d'altitudes", f"[{float(a.min()):.1f} ; {float(a.max()):.1f}]"),
    ]

    if a.size <= 60_000_000:
        z = a.astype("float32").filled(np.nan)
        p = np.pad(z, 1, constant_values=np.nan)
        centre = p[1:-1, 1:-1]
        plus_bas = np.zeros(centre.shape, dtype=bool)
        voisin_valide = np.zeros(centre.shape, dtype=bool)
        for dy in range(3):
            for dx in range(3):
                if dy == 1 and dx == 1:
                    continue
                v = p[dy:dy + h, dx:dx + w]
                plus_bas |= v <= centre
                voisin_valide |= np.isfinite(v)
        puits = np.isfinite(centre) & voisin_valide & ~plus_bas
        lignes.append(("Puits (pixels plus bas que leurs 8 voisins)", f"{int(puits.sum()):,}"))
    else:
        lignes.append(("Puits", "non calculés (raster trop volumineux)"))

    print(pd.DataFrame(lignes, columns=["Indicateur", "État constaté"]).to_string(index=False))
    print("  Corrections prévues (NON appliquées en dry-run) : reprojection vers EPSG:26191,")
    print("  masquage du NoData / de la mer, remplissage des puits (Priority-Flood).")


# =============================================================================
# PROGRAMME PRINCIPAL
# =============================================================================
def main():
    ap = argparse.ArgumentParser(description="Rapport dry-run : audit géométrique et topologique")
    ap.add_argument("--racine", help="Racine du projet (dossier contenant donnees_*)")
    ap.add_argument("--dry-run", action="store_true", default=True,
                    help="Mode rapport seul (ce script n'écrit jamais de fichier)")
    args = ap.parse_args()

    racine = trouver_racine(args.racine)
    if racine is None or not racine.is_dir():
        print("[ERREUR] Racine du projet introuvable.")
        print("         Lance le script depuis le projet, ou passe --racine \"chemin\", ou définis GEOAI_RACINE.")
        sys.exit(1)

    entete("RAPPORT DRY-RUN : AUDIT GÉOMÉTRIQUE ET TOPOLOGIQUE (projet GeoAI Inondation Casablanca)")
    print(f"  Mode             : rapport seul (0 fichier écrit)")
    print(f"  Racine du projet : {racine}")
    print(f"  SCR cible        : {CRS_CIBLE}")

    emprise, f_emprise = charger_emprise(racine)
    print(f"  Emprise de test  : {f_emprise.name if f_emprise else 'indisponible (hors emprise non calculé)'}")

    # ---- 1. Désaccords topologiques réels
    entete("1. DÉSACCORDS TOPOLOGIQUES RÉELS DU THÈME (calculés sur les données)")

    cas_waterways(racine)

    # ---- 2. Audit de toutes les couches
    entete("2. TRAÇABILITÉ AVANT / APRÈS : AUDIT DES COUCHES VECTORIELLES")
    O = "donnees_decoupes/casablanca_settat/osm/"
    C = "donnees_traitees/casablanca_settat_clean/"
    catalogue = [
        ("Bâti (OSM)", [O + "gis_osm_buildings_a_free_1_casablanca_settat.gpkg",
                        C + "bati_casablanca_settat_clean.gpkg"], [("buildings",), ("bati",)], True, True),
        ("Routes", [O + "gis_osm_roads_free_1_casablanca_settat.gpkg",
                    C + "routes_casablanca_settat_reprojete.gpkg"], [("roads",), ("routes",)], True, False),
        ("Occupation du sol (OSM)", [O + "gis_osm_landuse_a_free_1_casablanca_settat.gpkg",
                                     C + "occupation_sol_casablanca_settat_clean.gpkg"],
         [("landuse",), ("occupation_sol",)], True, False),
        ("Équipements / POI (OSM)", [O + "gis_osm_pois_free_1_casablanca_settat.gpkg",
                                     C + "equipements_poi_casablanca_settat_clean.gpkg"],
         [("pois",), ("equipements_poi",)], True, False),
        ("Infrastructures de secours", [C + "infrastructures_secours_clean.gpkg"],
         [("secours",)], True, False),
        ("Waterways OSM", [O + "gis_osm_waterways_free_1_casablanca_settat.gpkg"],
         [("waterways",)], True, False),
       
        ("Limites des communes", [C + "communes_casablanca_settat_clean.gpkg"],
         [("commune",)], False, False),
    ]

    rapports, gdf_bati = [], None
    for nom, relatifs, alternatives, test_emprise, est_bati in catalogue:
        rap, g = auditer_couche(racine, nom, relatifs, alternatives,
                                emprise if test_emprise else None)
        rapports.append(rap)
        if est_bati and g is not None:
            gdf_bati = g

    df = pd.DataFrame(rapports)
    print(df.to_string(index=False))
    print("\n  Notes : « Doublons stricts » = géométrie ET attributs identiques ; « Hors emprise » = -1 si")
    print("  l'emprise n'est pas disponible ; « Entités après nettoyage » est une estimation")
    print("  (hors doublons et hors emprise), les géométries invalides étant réparées, pas supprimées.")

    # ---- 3. Bâti
    entete("3. DIAGNOSTIC DU BÂTI")
    if gdf_bati is None:
        print("  [ABSENT] Couche bâti introuvable : diagnostic non réalisé sur cette machine.")
    else:
        diagnostic_bati(gdf_bati)

    # ---- 4. MNT
    entete("4. AUDIT DU MODÈLE NUMÉRIQUE DE TERRAIN")
    audit_dem(racine)

    entete("FIN DU RAPPORT : aucun fichier écrit ni modifié")


if __name__ == "__main__":
    main()