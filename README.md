# Outils de pré-génération

Les outils de pré-génération font partie du projet open-source ROK4 (sous licence CeCILL-C) développé par les équipes du projet [Géoportail](https://www.geoportail.gouv.fr)([@Geoportail](https://twitter.com/Geoportail)) de l’[Institut National de l’Information Géographique et Forestière](https://ign.fr) ([@IGNFrance](https://twitter.com/IGNFrance)). Ils sont écrits en perl et travaillent en amont lors de la génération d'une pyramide raster ([BE4](#be4), [JOINCACHE](#joincache)) ou vecteur ([4ALAMO](#4alamo)), d'une recopie de pyramide ([PYR2PYR](#pyr2pyr)) ou du recalcul de tête d'une pyramide raster ([4HEAD](#4head))

Ces outils identifient le travail à réaliser et le répartissent dans des scripts BASH, selon un niveau de parallélisation choisi. C'est l'exécution de ces derniers qui écrit les dalles des pyramides.

Ces scripts utilisent les outils de [génération du projet](https://github.com/rok4/generation), ainsi que des commandes externes.

Il est possible que les scripts BASH sachent faire de la reprise sur erreur. Dans chaque dossier temporaire individuel, un fichier liste contient le travail déjà réalisé. Au lancement du script, si ce fichier liste existe déjà, il identifie la dernière dalle générée et ignorera toutes les instructions jusqu'à retomber sur cette dalle. On peut donc en cas d'erreur relancer le script sans paramétrage et reprendre où il en était à l'exécution précédente.

De même, un fichier .prog à côté du script peut être mis à jour avec le pourcentage de progression (calculé à partir des lignes du script).

## Installation depuis le paquet debian

Télécharger les paquets sur GitHub : 

* [Les librairies Core](https://github.com/rok4/core-perl/releases/)
* [Les outils](https://github.com/rok4/pregeneration/releases/)

```
apt install ./librok4-core-perl-<version>-linux-all.deb
apt install ./rok4-pregeneration-<version>-linux-all.deb
```

## Installation depuis les sources

Dépendances (paquets debian) :

* perl-base
* [librok4-core-perl](https://github.com/rok4/core-perl/releases/)
* libfindbin-libs-perl
* libmath-bigint-perl
* liblog-log4perl-perl
* libjson-parse-perl
* libjson-perl

```
perl Makefile.PL INSTALL_BASE=/usr VERSION=0.0.1 PREREQ_FATAL=1
make
make injectversion
make install
```

## Variables d'environnement utilisées dans les librairies ROK4::Core

Leur définition est contrôlée à l'usage.

* `ROK4_TMS_DIRECTORY` pour y chercher les Tile Matrix Sets. Ces derniers peuvent être téléchargés sur [GitHub](https://github.com/rok4/tilematrixsets/releases/), installés depuis le paquet debian et seront alors dans le dossier `/etc/rok4/tilematrixsets`.
* Pour le stockage CEPH
    - `ROK4_CEPH_CONFFILE`
    - `ROK4_CEPH_USERNAME`
    - `ROK4_CEPH_CLUSTERNAME`
* Pour le stockage S3
    - `ROK4_S3_URL`
    - `ROK4_S3_KEY`
    - `ROK4_S3_SECRETKEY`
* Pour le stockage SWIFT
    - `ROK4_SWIFT_AUTHURL`
    - `ROK4_SWIFT_USER`
    - `ROK4_SWIFT_PASSWD`
    - `ROK4_SWIFT_PUBLICURL`
    - Si authentification via Swift
        - `ROK4_SWIFT_ACCOUNT`
    - Si connection via keystone (présence de `ROK4_KEYSTONE_DOMAINID`)
        - `ROK4_KEYSTONE_DOMAINID`
        - `ROK4_KEYSTONE_PROJECTID`
* Pour configurer l'agent de requête (intéraction SWIFT et S3)
    - `ROK4_SSL_NO_VERIFY`
    - `HTTP_PROXY`
    - `HTTPS_PROXY`
    - `NO_PROXY`

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

#### Usage

`be4.pl --conf /home/IGN/conf.json [--help|--usage|--version]`

* `--help` Affiche le lien vers la documentation utilisateur de l'outil et quitte
* `--usage` Affiche le lien vers la documentation utilisateur de l'outil et quitte
* `--version` Affiche la version de l'outil et quitte
* `--conf <file path>` Execute l'outil en prenant en compte ce fichier de configuration

#### Détails

_Étape 1_
![BE4 étape 1](./docs/images/be4_part1.png)

_Étape 2 (QTree)_
![BE4 étape 2 QTree](./docs/images/be4_part2_qtree.png)

_Étape 2 (NNGraph)_
![BE4 étape 2 NNGraph](./docs/images/be4_part2_nngraph.png)


#### Exemples de configuration

Génération d'une nouvelle pyramide depuis des images géoréférencées type MNT, avec application d'un style de pente. Les styles peuvent être téléchargés sur [GitHub](https://github.com/rok4/styles/releases/), installés depuis le paquet debian et seront alors dans le dossier `/etc/rok4/styles`.

```json
{
    "logger": {
        "level": "INFO",
        "layout": "%5p : %m (%M) %n"
    },
    "datasources": [
        {
            "top": "0",
            "bottom": "<AUTO>",
            "source": {
                "type": "IMAGES",
                "directory": "/data/RGEALTI5M",
                "srs": "IGNF:LAMB93"
            }
        }
    ],
    "pyramid": {
        "type": "GENERATION",
        "name": "RGEALTI",
        "compression": "zip",
        "tms": "LAMB93_1M_MNT.json",
        "storage": {
            "type": "FILE",
            "root": "/data/tsatabin/PYRAMIDS"
        },
        "nodata": [0,0,0,0],
        "pixel": {
            "sampleformat": "UINT8",
            "samplesperpixel": 4
        }
    },
    "process": {
        "directories": {
            "scripts": "/scripts",
            "local_tmp": "/tmp",
            "shared_tmp": "/share"
        },
        "parallelization": 1,
        "style": "/etc/rok4/styles/montagne.json",
        "nodata": [-99999]
    }
}
```

Mise à jour par référence d'une pyramide S3 par moissonnage d'un service WMS

```json
{
    "logger": {
        "level": "INFO",
        "layout": "%5p : %m (%M) %n"
    },
    "datasources": [
        {
            "top": "<AUTO>",
            "bottom": "8",
            "source": {
                "type": "WMS",
                "area": {
                    "bbox": [5,45,6,46],
                    "srs": "EPSG:4326"
                },
                "layers": "GEOGRAPHICALGRIDSYSTEMS.PLANIGNV2",
                "url": "https://wxs.ign.fr/essentiels/geoportail/r/wms"
            }
        },
        {
            "top": "<AUTO>",
            "bottom": "12",
            "source": {
                "type": "WMS",
                "area": {
                    "bbox": [5,45,6,46],
                    "srs": "EPSG:4326"
                },
                "layers": "GEOGRAPHICALGRIDSYSTEMS.PLANIGNV2",
                "url": "https://wxs.ign.fr/essentiels/geoportail/r/wms"
            }
        }
    ],
    "pyramid": {
        "type": "UPDATE",
        "name": "PLANIGNV2_UPDATED",
        "pyramid_to_update": "s3://bucket/pyramides/PLANIGNV2.json",
    },
    "process": {
        "directories": {
            "scripts": "/scripts",
            "local_tmp": "/tmp",
            "shared_tmp": "/share"
        },
        "parallelization": 1
    }
}
```

### JOINCACHE

L'outil JOINCACHE génèrent une pyramide raster à partir d'autres pyramide raster compatibles (même TMS, dalles de même dimensions, canaux au même format). La composition se fait verticalement (choix des pyramides sources par niveau) et horizontalement (choix des pyramides source par zone au sein d'un niveau). La fusion de plusieurs dalles sources peut se faire selon plusieurs méthodes (masque, alpha top, multiplication)

Stockages gérés : FICHIER, CEPH, S3, SWIFT

Parallélisable, reprise sur erreur, progression.

Outils de génération utilisés :

* cache2work
* overlayNtiff
* work2cache

#### Usage

`joincache.pl --conf /home/IGN/conf.json [--help|--usage|--version]`

* `--help` Affiche le lien vers la documentation utilisateur de l'outil et quitte
* `--usage` Affiche le lien vers la documentation utilisateur de l'outil et quitte
* `--version` Affiche la version de l'outil et quitte
* `--conf <file path>` Execute l'outil en prenant en compte ce fichier de configuration principal

#### Détails

_Étape 1_
![JOINCACHE étape 1](./docs/images/joinCache_part1.png)

_Étape 2_
![JOINCACHE étape 2](./docs/images/joinCache_part2.png)


#### Exemples de configuration

Génération d'une pyramide par fusion de 2 pyramides CEPH, avec conversion des canaux

```json
{
    "logger": {
        "level": "WARN",
        "layout": "%5p : %m (%M) %n",
        "file": "/var/log/joincache.log"
    },
    "datasources": [
        {
            "top": "0",
            "bottom": "10",
            "source": {
                "type": "PYRAMIDS",
                "area": {
                    "bbox": [
                        -572324.2901945519,
                        5061666.243846581,
                        1064224.752260841,
                        6637050.045897862
                    ]
                },
                "descriptors": [
                    "ceph:///pool/pyramids/NORD.json",
                    "ceph:///pool/pyramids/SUD.json"
                ]
            }
        }
    ],
    "pyramid": {
        "name": "ENTIER",
        "root": "pool",
        "pixel": {
            "samplesperpixel": 1,
            "sampleformat": "UINT8"
        },
        "nodata": [255],
        "compression": "png"
    },
    "process": {
        "directories": {
            "scripts": "/scripts",
            "local_tmp": "/tmp",
            "shared_tmp": "/share"
        },
        "parallelization": 1,
        "merge_method": "TOP",
        "mask": true
    }
}
```

### 4ALAMO

L'outil 4ALAMO génèrent une pyramide vecteur à partir d'une base de données PostgreSQL ou de fichiers vecteurs. Ils permettent de mettre à jour une pyramide vecteur existante.

Stockages gérés : FICHIER, CEPH, S3, SWIFT

Parallélisable, reprise sur erreur, progression.

Outils de génération utilisés :

* pbf2cache

Outils externes utilisés :

* ogr2ogr
* tippecanoe

#### Usage

`4alamo.pl --conf /home/IGN/conf.json [--help|--usage|--version]`

* `--help` Affiche le lien vers la documentation utilisateur de l'outil et quitte
* `--usage` Affiche le lien vers la documentation utilisateur de l'outil et quitte
* `--version` Affiche la version de l'outil et quitte
* `--conf <file path>` Execute l'outil en prenant en compte ce fichier de configuration

#### Détails

_Étape 1_
![4ALAMO étape 1](./docs/images/4alamo_part1.png)

_Étape 2_
![4ALAMO étape 2](./docs/images/4alamo_part2.png)

#### Exemples de configuration

Mise à jour par injection d'une pyramide SWIFT à partir de tables PostgreSQL

```json
{
   "logger": {
      "level": "ERROR",
      "layout": "%5p : %m (%M) %n"
   },
   "datasources": [
      {
         "top": "4",
         "bottom": "9",
         "source": {
            "type": "POSTGRESQL",
            "area": {
               "bbox": [10,45,15,50]
            },
            "srs": "EPSG:4326",
            "db" : {
               "user" : "reader",
               "password" : "reader",
               "database" : "geodata",
               "host" : "postgresql.internal"
            },
            "tables" : [
               {
                  "schema" : "essentiels",
                  "native_name" : "region",
                  "attributes" : ["*"]
               }
            ]
         }
      },
      {
         "top": "10",
         "bottom": "12",
         "source": {
            "type": "POSTGRESQL",
            "area": {
               "bbox": [10,45,15,50]
            },
            "srs": "EPSG:4326",
            "db" : {
               "user" : "reader",
               "password" : "reader",
               "database" : "geodata",
               "host" : "postgresql.internal"
            },
            "tables" : [
               {
                  "schema" : "essentiels",
                  "native_name" : "departement",
                  "attributes" : ["*"]
               },
               {
                  "schema" : "essentiels",
                  "native_name" : "region",
                  "attributes" : ["*"]
               }
            ]
         }
      }
   ],
   "pyramid": {
      "type": "INJECTION",
      "pyramid_to_inject": "swift:///container/pyramids/LIMADM.json"
   },
    "process": {
        "directories": {
            "scripts": "/scripts",
            "local_tmp": "/tmp",
            "shared_tmp": "/share"
        },
        "parallelization": 10
    }
}
```

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

#### Usage

`pyr2pyr.pl --conf /home/IGN/conf.json [--help|--usage|--version]`

* `--help` Affiche le lien vers la documentation utilisateur de l'outil et quitte
* `--usage` Affiche le lien vers la documentation utilisateur de l'outil et quitte
* `--version` Affiche la version de l'outil et quitte
* `--conf <file path>` Execute l'outil en prenant en compte ce fichier de configuration

#### Détails

_Étape 1_
![PYR2PYR étape 1](./docs/images/pyr2pyr_part1.png)

_Étape 2_
![PYR2PYR étape 2](./docs/images/pyr2pyr_part2.png)


#### Exemples de configuration

Recopie d'une pyramide CEPH -> SWIFT

```json
{
    "logger": {
        "level": "DEBUG",
        "layout": "%5p : %m (%M) %n"
    },
    "from": {
        "descriptor": "ceph:///pool/pyramids/SCAN1000.json"
    },
    "to": {
        "name": "pyramids/SCAN1000",
        "storage": {
            "type": "SWIFT",
            "root": "container"
        }
    },
    "process": {
        "directories": {
            "scripts": "/scripts",
            "local_tmp": "/tmp",
            "shared_tmp": "/share"
        },
        "parallelization": 32,
        "follow_links": true
    }
}
```



