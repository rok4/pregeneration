# Outils de pré-génération

Les outils de prégénération travaillent en amont lors de la génération d'une pyramide raster ([BE4](#be4), [JOINCACHE](#joincache)) ou vecteur ([4ALAMO](#4alamo)), d'une recopie de pyramide ([PYR2PYR](#pyr2pyr)) ou du recalcul de tête d'une pyramide raster ([4HEAD](#4head))

Ces outils, écrits en perl, identifient le travail à réaliser et le répartissent dans des scripts BASH, selon un niveua de parallélisation choisi. C'est l'exécution de ces derniers qui écrit les dalles des pyramides.

Ces scripts utilisent des commandes du projet ROK4 (dépôt `generation`), ainsi que des commandes externes.

Il est possible que les scripts BASH sachent faire de la reprise sur erreur. Dans chaque dossier temporaire individuel, un fichier liste contient le travail déjà réalisé. Au lancement du script, si ce fichier liste existe déjà, il identifie la dernière dalle générée et ignorera toutes les instructions jusqu'à retomber sur cette dalle. On peut donc en cas d'erreur relancer le script sans paramétrage et reprendre où il en était à l'exécution précédente.

De même, un fichier .prog à côté du script peut être mis à jour avec le pourcentage de progression (calculé à partir des lignes du script).

- [Récupération du projet](#récupération-du-projet)
- [Dépendances](#dépendances)
- [Installation](#installation)
- [Présentation des outils](#présentation-des-outils)
  - [BE4](#be4)
  - [JOINCACHE](#joincache)
  - [4ALAMO](#4alamo)
  - [4HEAD](#4head)
  - [PYR2PYR](#pyr2pyr)

## Récupération du projet

``

## Dépendances

* Submodule GIT
    * `rok4/core-perl`
* Paquets debian
    * perl-base
    * libgdal-perl
    * libpq-dev
    * gdal-bin
    * libfile-find-rule-perl
    * libfile-copy-link-perl
    * libconfig-ini-perl
    * libdbi-perl
    * libdbd-pg-perl
    * libdevel-size-perl
    * libdigest-sha-perl
    * libfile-map-perl
    * libfindbin-libs-perl
    * libhttp-message-perl
    * liblwp-protocol-https-perl
    * libmath-bigint-perl
    * libterm-progressbar-perl
    * liblog-log4perl-perl
    * libjson-parse-perl
    * libjson-perl
    * libtest-simple-perl
    * libxml-libxml-perl
    * libamazon-s3-perl

## Installation

`PERL5LIB=/usr/local/lib/perl5/ perl Makefile.PL INSTALL_BASE=/usr/local VERSION=0.0.1`


## Présentation des outils

### BE4

L'outil BE4 génère une pyramide raster à partir d'images géoréférencées ou d'un service WMS. Il permet de mettre à jour une pyramide raster existante. Si des images sont en entrée, elles peuvent être converties à la volée dans le format de la pyramide en sortie. Il est également possible d'appliquer aux images en entrée un style, comme le calcul de pente à partir de données MNT.

Stockages gérés : FICHIER, CEPH, S3, SWIFT

Parallélisable, reprise sur erreur, progression.

Outils de génération utilisés :

* cache2work
* checkWork
* composeNtiff
* decimateNtiff
* merge4tiff
* mergeNtiff
* work2cache

Outils externes utilisés :

* wget

_Étape 1_
![BE4 étape 1](../docs/images/be4_part1.png)

_Étape 2 (QTree)_
![BE4 étape 2 QTree](../docs/images/be4_part2_qtree.png)
_Étape 2 (NNGraph)_
![BE4 étape 2 NNGraph](../docs/images/be4_part2_nngraph.png)

[Détails](./bin/be4.md)

### JOINCACHE

L'outil JOINCACHE génèrent une pyramide raster à partir d'autres pyramide raster compatibles (même TMS, dalles de même dimensions, canaux au même format). La composition se fait verticalement (choix des pyramides sources par niveau) et horizontalement (choix des pyramides source par zone au sein d'un niveau). La fusion de plusieurs dalles sources peut se faire selon plusieurs méthodes (masque, alpha top, multiplication)

Stockages gérés : FICHIER, CEPH, S3, SWIFT

Parallélisable, reprise sur erreur, progression.

Outils de génération utilisés :

* cache2work
* overlayNtiff
* work2cache


_Étape 1_
![JOINCACHE étape 1](../docs/images/joinCache_part1.png)

_Étape 2_
![JOINCACHE étape 2](../docs/images/joinCache_part2.png)

[Détails](./main/joincache.md)

### 4ALAMO

L'outil 4ALAMO génèrent une pyramide vecteur à partir d'une base de données PostgreSQL. Ils permettent de mettre à jour une pyramide vecteur existante.

Stockages gérés : FICHIER, CEPH, S3, SWIFT

Parallélisable, reprise sur erreur, progression.

Outils de génération utilisés :

* pbf2cache

Outils externes utilisés :

* ogr2ogr
* tippecanoe

_Étape 1_
![4ALAMO étape 1](../docs/images/ROK4GENERATION/4alamo_part1.png)

_Étape 2_
![4ALAMO étape 2](../docs/images/ROK4GENERATION/4alamo_part2.png)

[Détails](./bin/4alamo.md)

### 4HEAD

Cet outil permet de regénérer des niveaux de la pyramide en partant d'un de ses niveaux. La pyramide est modifiée et sa liste, qui fait foi en terme de contenu de la pyramide, est mise à jour pour toujours correspondre au contenu final de la pyramide. L'outil perl modifie la liste et le descripteur et génère des script shell dont l'exécution modifiera les dalles de la pyramide. Seuls les niveaux entre celui de référence (non inclus) et le niveau du haut fournis (inclus) sont modifiés. Potentiellement des nouveaux niveaux sont ajoutés (lorsque l'outil est utilisé pour construire la tête de la pyramide qui n'existait pas).

Par défaut, l'outil génère deux scripts (`SCRIPT_1.sh` et `SCRIPT_FINISHER.sh`). Si on précise un niveau de parallélisation (via l'option `--parallel`) de N, on aura alors N scripts `SCRIPT_X.sh` et toujours `SCRIPT_FINISHER.sh` pour regénérer l'ensemble des dalles. Tous les scripts `SCRIPT_X.sh` peuvent être exécuter en parallèle, mais il faut attendre la fin de tous ces scripts pour lancer `SCRIPT_FINISHER.sh`.

Le script `main.sh` permet de lancer proprement tous ces scripts sur la même machine. Il ne permet donc pas de répartir les exécutions sur un pool de machine. L'appel à faire est loggé en fin d'exécution de `4head.pl`.

Stockages gérés : FICHIER, CEPH, S3, SWIFT

Parallélisable.

Types de pyramides gérés : RASTER QTREE

##### Commande

`4head.pl --pyr file:///home/ign/PYRAMID.pyr --tmsdir /home/ign/TMS/ --reference-level 19 --top-level 4 --tmp /home/ign/tmp/ --scripts /home/ign/scripts/ [--parallel 10] [--help|--usage|--version]`

##### Options

* `--help` Affiche le lien vers la documentation utilisateur de l'outil et quitte
* `--usage` Affiche le lien vers la documentation utilisateur de l'outil et quitte
* `--version` Affiche la version de l'outil et quitte
* `--pyr` Précise le chemin vers le descripteur de la pyramide à modifier. Ce chemin est préfixé par le type de stockage du descripteur : `file://`, `s3://`, `ceph://` ou `swift://`
* `--tmsdir` Précise le dossier contenant au moins le TMS utilisé par la pyramide à modifier
* `--reference-level` Précise le niveau de la pyramide d'où partir pour regénérer les niveaux supérieurs
* `--top-level` Précise le niveau jusqu'auquel regénérer les dalles
* `--tmp` Précise un dossier à utiliser comme espace temporaire de génération. Il doit être partagé entre tous les scripts
* `--script` Précise un dossier où écrire les scripts
* `--parallel` Précise le nombre de scripts pour modifier les dalles du niveau au dessus du niveau de référence (Optionnel, 1 par défaut)

### PYR2PYR

Outil : `pyr2pyr.pl`

Cet outil copie une pyramide d'un stockage à un autre.

Conversions possibles :

* FICHIER -> FICHIER, CEPH, S3, SWIFT
* CEPH -> FICHIER, CEPH, S3, SWIFT
* S3 -> FICHIER

Parallélisable, reprise sur erreur, progression.

_Étape 1_
![PYR2PYR étape 1](../docs/images/pyr2pyr_part1.png)

_Étape 2_
![PYR2PYR étape 2](../docs/images/pyr2pyr_part2.png)

[Détails](./bin/pyr2pyr.md)