@echo off
setlocal EnableExtensions

REM =============================================================================
REM  import_postgis.bat - Import complet des donnees nettoyees dans PostGIS
REM  Projet : GeoAI Inondation Casablanca
REM
REM  PORTABLE : aucun chemin ni mot de passe en dur.
REM  Chaque collaborateur copie config_local.example.bat en config_local.bat
REM  (fichier NON versionne) et adapte uniquement ses propres parametres.
REM  Prerequis : PostgreSQL + PostGIS, GDAL/OGR (QGIS, OSGeo4W ou conda).
REM =============================================================================

REM ---------- 1. VALEURS PAR DEFAUT ----------
set "SCRIPT_DIR=%~dp0"

REM Racine du projet : le dossier du script s'il contient donnees_traitees, sinon son parent
set "ROOT=%SCRIPT_DIR:~0,-1%"
if not exist "%ROOT%\donnees_traitees" for %%I in ("%SCRIPT_DIR%..") do set "ROOT=%%~fI"

set "DB=geoai_casablanca"
set "PGHOST=localhost"
set "PGPORT=5432"
set "PGUSER=postgres"
set "RESET_DB=1"
set "ASSUME_YES=0"
set "NB_ERR=0"

REM ---------- 2. CONFIGURATION LOCALE (ecrase les valeurs par defaut) ----------
if exist "%SCRIPT_DIR%config_local.bat" call "%SCRIPT_DIR%config_local.bat"
if not exist "%SCRIPT_DIR%config_local.bat" echo [INFO] Pas de config_local.bat : valeurs par defaut utilisees.

if not defined DATA_DIR set "DATA_DIR=%ROOT%\donnees_traitees\casablanca_settat_clean"
if not defined SQL_SCHEMA set "SQL_SCHEMA=%SCRIPT_DIR%schema_postgis.sql"
if not exist "%SQL_SCHEMA%" set "SQL_SCHEMA=%ROOT%\schema_postgis.sql"

REM ---------- 3. OUTILS : psql et ogr2ogr (detection automatique) ----------
if defined PG_BIN set "PATH=%PG_BIN%;%PATH%"
where psql >nul 2>&1
if errorlevel 1 for /d %%D in ("C:\Program Files\PostgreSQL\*") do if exist "%%D\bin\psql.exe" set "PATH=%%D\bin;%PATH%"

if defined GDAL_BIN set "PATH=%GDAL_BIN%;%PATH%"
call :verifier_pg_driver
if errorlevel 1 call :trouver_gdal

where psql >nul 2>&1
if errorlevel 1 goto :err_psql
call :verifier_pg_driver
if errorlevel 1 goto :err_gdal

if not exist "%SQL_SCHEMA%" goto :err_schema
if not exist "%DATA_DIR%" goto :err_data

REM ---------- 4. MOT DE PASSE (jamais stocke dans le depot) ----------
if not defined PGPASSWORD set /p "PGPASSWORD=Mot de passe PostgreSQL de %PGUSER% : "

echo.
echo =============================================================
echo  PARAMETRES UTILISES
echo =============================================================
echo  Base        : %DB%  (%PGUSER%@%PGHOST%:%PGPORT%)
echo  Donnees     : %DATA_DIR%
echo  Schema SQL  : %SQL_SCHEMA%
echo  Remise a zero de la base : %RESET_DB%
echo  ogr2ogr utilise :
where ogr2ogr
ogr2ogr --version
psql --version

REM ---------- 5. CONNEXION ET CREATION DE LA BASE ----------
psql -h %PGHOST% -p %PGPORT% -U %PGUSER% -d postgres -c "SELECT 1;" >nul
if errorlevel 1 goto :err_connexion

psql -h %PGHOST% -p %PGPORT% -U %PGUSER% -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='%DB%'" | findstr 1 >nul
if errorlevel 1 psql -h %PGHOST% -p %PGPORT% -U %PGUSER% -d postgres -c "CREATE DATABASE %DB%;"

REM ---------- 6. REMISE A ZERO (evite les doublons si on relance) ----------
if "%RESET_DB%"=="1" call :reset
if errorlevel 1 goto :fin

psql -h %PGHOST% -p %PGPORT% -U %PGUSER% -d %DB% -c "CREATE EXTENSION IF NOT EXISTS postgis;"
if errorlevel 1 goto :err_postgis

echo.
echo =============================================================
echo  ETAPE 0 - Creation du schema (DDL)
echo =============================================================
psql -h %PGHOST% -p %PGPORT% -U %PGUSER% -d %DB% -v ON_ERROR_STOP=1 -f "%SQL_SCHEMA%"
if errorlevel 1 goto :err_ddl
echo [OK] schema cree

REM ---------- 7. IMPORT DES COUCHES ----------
REM  Arguments : fichier  couche_source  table_cible  type_geometrie
REM  Le type doit correspondre a celui declare dans schema_postgis.sql.
REM  commune en premier (cles etrangeres).
call :importer "%DATA_DIR%\communes_casablanca_settat_clean.gpkg"         commune        commune                 MULTIPOLYGON
call :importer "%DATA_DIR%\maille_250m_casablanca_settat.gpkg"           maille         maille                  POLYGON
call :importer "%DATA_DIR%\bati_casablanca_settat_clean.gpkg"             bati           bati                    MULTIPOLYGON
call :importer "%DATA_DIR%\routes_casablanca_settat_reprojete.gpkg"       routes         route                   MULTILINESTRING
call :importer "%DATA_DIR%\oued_detaille_casablanca_settat_clean.gpkg"    oued_detaille  cours_eau               MULTILINESTRING
call :importer "%DATA_DIR%\occupation_sol_casablanca_settat_clean.gpkg"   landuse        occupation_sol          MULTIPOLYGON
call :importer "%DATA_DIR%\equipements_poi_casablanca_settat_clean.gpkg"  poi_filtre     equipement_poi          POINT
call :importer "%DATA_DIR%\infrastructures_secours_clean.gpkg"            poi_secours    infrastructure_secours  POINT

REM ---------- 8. SEQUENCES, STATISTIQUES ET INDEX ----------
REM  commune et maille sont importees avec leurs id d'origine : on recale les sequences SERIAL
echo.
echo =============================================================
echo  RESYNCHRONISATION DES SEQUENCES (commune, maille)
echo =============================================================
psql -h %PGHOST% -p %PGPORT% -U %PGUSER% -d %DB% -c "SELECT setval(pg_get_serial_sequence('commune','id'), COALESCE((SELECT MAX(id) FROM commune),1)); SELECT setval(pg_get_serial_sequence('maille','id'), COALESCE((SELECT MAX(id) FROM maille),1));"

echo.
echo =============================================================
echo  VACUUM ANALYZE (statistiques pour le planificateur)
echo =============================================================
psql -h %PGHOST% -p %PGPORT% -U %PGUSER% -d %DB% -c "VACUUM ANALYZE;"

echo.
echo =============================================================
echo  INDEX SPATIAUX GIST (crees par schema_postgis.sql, bloc 7)
echo =============================================================
psql -h %PGHOST% -p %PGPORT% -U %PGUSER% -d %DB% -c "SELECT tablename, indexname FROM pg_indexes WHERE schemaname='public' AND indexdef ILIKE '%%gist%%' ORDER BY tablename;"

REM ---------- 9. VERIFICATION : comptage par table ----------
echo.
echo =============================================================
echo  VERIFICATION : comptage par table
echo =============================================================
psql -h %PGHOST% -p %PGPORT% -U %PGUSER% -d %DB% -c "SELECT 'bati' AS table_name, COUNT(*) AS n FROM bati UNION ALL SELECT 'route', COUNT(*) FROM route UNION ALL SELECT 'cours_eau', COUNT(*) FROM cours_eau UNION ALL SELECT 'occupation_sol', COUNT(*) FROM occupation_sol UNION ALL SELECT 'equipement_poi', COUNT(*) FROM equipement_poi UNION ALL SELECT 'infrastructure_secours', COUNT(*) FROM infrastructure_secours UNION ALL SELECT 'commune', COUNT(*) FROM commune UNION ALL SELECT 'maille', COUNT(*) FROM maille ORDER BY table_name;"

echo.
echo =============================================================
echo  IMPORT TERMINE - couches en erreur ou absentes : %NB_ERR%
echo =============================================================
goto :fin


REM =============================================================================
REM  SOUS-ROUTINES
REM =============================================================================
:importer
if not exist "%~1" echo [ABSENT] %~1 & set /a NB_ERR+=1 & exit /b 0
echo.
echo === %~3 : couche %~2, geometrie %~4 ===
ogr2ogr -f PostgreSQL "PG:host=%PGHOST% port=%PGPORT% dbname=%DB% user=%PGUSER%" "%~1" %~2 -nln %~3 -append -nlt %~4 -a_srs EPSG:26191 -gt 65536 --config PG_USE_COPY YES
if errorlevel 1 (
    echo [ERREUR] %~3
    set /a NB_ERR+=1
) else (
    echo [OK] %~3
)
exit /b 0

:reset
echo.
echo ATTENTION : tout le schema public de la base %DB% va etre supprime puis recree.
if "%ASSUME_YES%"=="1" goto :reset_go
set "REP="
set /p "REP=Taper OUI pour continuer : "
if /i not "%REP%"=="OUI" echo Annule. & exit /b 1
:reset_go
psql -h %PGHOST% -p %PGPORT% -U %PGUSER% -d %DB% -c "DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public;"
exit /b %errorlevel%

:verifier_pg_driver
REM Succes (0) seulement si ogr2ogr existe ET possede le pilote PostgreSQL/PostGIS
where ogr2ogr >nul 2>&1
if errorlevel 1 exit /b 1
ogr2ogr --formats 2>nul | findstr /c:"PostgreSQL -vector-" >nul
exit /b %errorlevel%

:trouver_gdal
REM Le ogr2ogr courant n'a pas le pilote PostgreSQL : on cherche celui de QGIS / OSGeo4W
REM (il passe en tete du PATH, avec son propre GDAL_DATA et PROJ_LIB)
if exist "C:\OSGeo4W\bin\ogr2ogr.exe" set "PATH=C:\OSGeo4W\bin;%PATH%"
for /d %%D in ("C:\Program Files\QGIS*") do if exist "%%D\bin\o4w_env.bat" set "QGIS_DIR=%%D"
if defined QGIS_DIR call "%QGIS_DIR%\bin\o4w_env.bat"
exit /b 0


REM =============================================================================
REM  MESSAGES D'ERREUR
REM =============================================================================
:err_psql
echo [ERREUR] psql introuvable. Renseigne PG_BIN dans config_local.bat
echo          ex. : set "PG_BIN=C:\Program Files\PostgreSQL\18\bin"
goto :fin
:err_gdal
echo [ERREUR] Aucun ogr2ogr avec le pilote PostgreSQL n'a ete trouve.
echo          - Installe QGIS (son GDAL inclut le pilote), puis relance ce script
echo            depuis l'OSGeo4W Shell ; ou renseigne GDAL_BIN dans config_local.bat.
echo          - Avec conda : conda install -c conda-forge libgdal-pg
echo          Test : ogr2ogr --formats ^| findstr "PostgreSQL"
goto :fin
:err_schema
echo [ERREUR] schema_postgis.sql introuvable : %SQL_SCHEMA%
echo          Renseigne SQL_SCHEMA dans config_local.bat.
goto :fin
:err_data
echo [ERREUR] Dossier de donnees introuvable : %DATA_DIR%
echo          Genere les couches nettoyees ou renseigne DATA_DIR dans config_local.bat.
goto :fin
:err_connexion
echo [ERREUR] Connexion PostgreSQL impossible (%PGUSER%@%PGHOST%:%PGPORT%).
echo          Verifie que le service tourne, le port et le mot de passe.
goto :fin
:err_postgis
echo [ERREUR] Extension PostGIS indisponible. Installe-la (Stack Builder) puis relance.
goto :fin
:err_ddl
echo [ERREUR] Echec de schema_postgis.sql : voir le message ci-dessus.
goto :fin

:fin
if not defined NO_PAUSE pause
endlocal