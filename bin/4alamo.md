# 4ALAMO

[Vue générale](../../README.md#la-suite-4alamo)

- [Usage](#usage)
  - [Commandes](#commandes)
  - [Options](#options)
- [La configuration principale](#la-configuration-principale)
  - [Section `logger`](#section-logger)
    - [Paramètres](#paramètres)
    - [Exemple](#exemple)
  - [Section `datasource`](#section-datasource)
    - [Paramètres](#paramètres-1)
    - [Exemple](#exemple-1)
  - [Section `pyramid`](#section-pyramid)
    - [Paramètres](#paramètres-2)
    - [Exemple](#exemple-2)
  - [Section `process`](#section-process)
    - [Paramètres](#paramètres-3)
    - [Exemple](#exemple-3)
- [La configuration des sources de données](#la-configuration-des-sources-de-données)
  - [Paramètres](#paramètres-4)
  - [Exemple](#exemple-4)
- [Résumé des fichiers et dossiers manipulés](#résumé-des-fichiers-et-dossiers-manipulés)

## Usage

### Commandes

* `4alamo-file.pl --conf /home/IGN/conf.txt [--env /home/IGN/env.txt] [--help|--usage|--version]`
* `4alamo-ceph.pl --conf /home/IGN/conf.txt [--env /home/IGN/env.txt] [--help|--usage|--version]`

### Options

* `--help` Affiche le lien vers la documentation utilisateur de l'outil et quitte
* `--usage` Affiche le lien vers la documentation utilisateur de l'outil et quitte
* `--version` Affiche la version de l'outil et quitte
* `--conf <file path>` Execute l'outil en prenant en compte ce fichier de configuration principal
* `--env <file path>` Execute l'outil en prenant en compte ce fichier d'environnement'

## La configuration principale

La configuration principale est au format INI :
```
[ section ]
parameter = value
```

Il est possible d'utiliser une configuration d'environnement, au même format, dont les valeurs seront surchargées par celles dans la configuration principale.

### Section `logger`

#### Paramètres

| Paramètre | Description                                                                                                                                                                                          | Obligatoire ou valeur par défaut |
| --------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------- |
| log_path  | Dossier dans lequel écrire les logs. Les logs ne sont pas écrits dans un fichier si ce paramètre n'est pas fourni.                                                                                   |                                  |
| log_file  | Fichier dans lequel écrire les logs, en plus de la sortie standard. Les logs ne sont pas écrits dans un fichier si ce paramètre n'est pas fourni. Le fichier écrit sera donc `<log_path>/<log_file>` |                                  |
| log_level | Niveau de log : DEBUG - INFO - WARN - ERROR - ALWAYS                                                                                                                                                 | `WARN`                           |


#### Exemple
```
[ logger ]
log_path = /var/log
log_file = 4alamo_2019-02-01.txt
log_level = INFO
```

### Section `datasource`

#### Paramètres

| Paramètre     | Description                                                                      | Obligatoire ou valeur par défaut |
| ------------- | -------------------------------------------------------------------------------- | -------------------------------- |
| filepath_conf | Chemin vers le fichier de configuration de la source de données (au format JSON) | obligatoire                      |

#### Exemple
```
[ datasource ]
filepath_conf = /home/IGN/SOURCE/sources.json
```

### Section `pyramid`

#### Paramètres

| Paramètre     | Description                                                             | Obligatoire ou valeur par défaut |
| ------------- | ----------------------------------------------------------------------- | -------------------------------- |
| pyr_name_new  | Nom de la nouvelle pyramide. Ne peut pas contenir de `/` pour un stockage fichier                                             | obligatoire                      |
| image_width   | Nombre de tuiles dans une dalle dans le sens de la largeur              | `16`                             |
| image_height  | Nombre de tuiles dans une dalle dans le sens de la hauteur              | `16`                             |
| tms_name      | Nom du Tile Matrix Set de la pyramide, avec l'extension `.json`          | obligatoire si pas d'ancêtre     |
| tms_path      | Dossier contenant le TMS                                                | obligatoire                      |
| pyr_level_top | Niveau du haut de la pyramide, niveau haut du TMS utilisé si non fourni |                                  |

##### Stockage de la pyramide

| Type de stockage | Paramètre          | Description                                                                 | Obligatoire ou valeur par défaut |
| ---------------- | ------------------ | --------------------------------------------------------------------------- | -------------------------------- |
| FILE             | `pyr_data_path`           | Dossier racine de stockage de la pyramide                                   | obligatoire                      |
| FILE             | `dir_depth`               | Nombre de sous-dossiers utilisé dans l'arborescence pour stocker les dalles | `2` si pas d'ancêtre             |
| CEPH             | `pyr_data_pool_name`      |                                                                             | obligatoire                      |
| S3               | `pyr_data_bucket_name`    |                                                                             | obligatoire                      |
| SWIFT            | `pyr_data_container_name` |                                                                             | obligatoire                      |

Dans le cas du stockage objet, certaines variables d'environnement doivent être définies sur les machines d'exécution :

* CEPH
    - `ROK4_CEPH_CONFFILE`
    - `ROK4_CEPH_USERNAME`
    - `ROK4_CEPH_CLUSTERNAME`
* S3
    - `ROK4_S3_URL`
    - `ROK4_S3_KEY`
    - `ROK4_S3_SECRETKEY`
* SWIFT
    * Toujours
        - `ROK4_SWIFT_AUTHURL`
        - `ROK4_SWIFT_USER`
        - `ROK4_SWIFT_PASSWD`
        - `ROK4_SWIFT_PUBLICURL`
    * Si authentification native, sans Keystone
        - `ROK4_SWIFT_ACCOUNT`
    * Si authentification avec Keystone (présence de `ROK4_KEYSTONE_DOMAINID`)
        - `ROK4_KEYSTONE_DOMAINID`
        - `ROK4_KEYSTONE_PROJECTID`

##### Cas d'une pyramide ancêtre

| Paramètre   | Description                                                                                               | Obligatoire ou valeur par défaut        |
| ----------- | --------------------------------------------------------------------------------------------------------- | --------------------------------------- |
| update_pyr  | Accès au descripteur de la pyramide à mettre à jour. La présence de ce paramètre implique une mise à jour |                                         |
| update_mode | Mode de mise à jour                                                                                       | obligatoire si `update_pyr` est présent |

Valeurs pour `update_pyr` : le chemin est préfixé par le type de stockage du descripteur : `file://`, `s3://`, `ceph://` ou `swift://`

Valeurs pour `update_mode` :

* `slink` : une nouvelle pyramide est créée, et les dalles de la pyramide ancêtre sont référencées avec un lien symbolique ou un objet symbolique
* `hlink` : disponible pour le stockage fichier uniquement, une nouvelle pyramide est créée, et les dalles de la pyramide ancêtre sont référencées avec un lien physique
* `copy` : une nouvelle pyramide est créée, et les dalles de la pyramide ancêtre sont recopiée dans la nouvelle pyramide
* `inject` : il n'y a pas de nouvelle pyramide créée, et la pyramide ancêtre est modifiée

Seuls les TMS QuadTree PM et WGS84G sont gérés par tippecanoe, donc par 4alamo.

#### Exemple

```
[ pyramid ]

pyr_data_path = /home/IGN/PYRAMIDS
pyr_name_new = BDTOPO
pyr_level_top = 6

tms_name = PM.json
tms_path = /home/IGN/TMS

dir_depth = 2
image_width = 16
image_height = 16
```

### Section `process`

#### Paramètres

| Paramètre        | Description                                                                                             | Obligatoire ou valeur par défaut |
| ---------------- | ------------------------------------------------------------------------------------------------------- | -------------------------------- |
| job_number       | Niveau de parallélisation de la génération de la pyramide.                                              | obligatoire                      |
| path_temp        | Dossier temporaire propre à chaque script. Un sous dossier au nom de la pyramide et du script sera créé | obligatoire                      |
| path_temp_common | Dossier temporaire commun à tous les scripts. Un sous dossier COMMON sera créé                          | obligatoire                      |
| path_shell       | Dossier où écrire les scripts                                                                           | obligatoire                      |

#### Exemple
```
[ process ]
path_temp = /tmp
path_temp_common = /mnt/share/
path_shell  = /home/IGN/SCRIPT/
job_number = 4
```

## La configuration des sources de données

Pour générer une pyramide vecteur, il faut renseigner pour chaque niveau de coupure (niveau pour lequel les sources de données sont différentes) le serveur PostgreSQL, les tables et attributs à utiliser ainsi que l'étendue sur laquelle les utiliser. Le fichier est au format JSON.

### Paramètres

* `Identifiant du niveau` : correpondant à ceux du TMS utilisé.
    - `tippecanoe_options` : options d'appel à tippecanoe. Optionnel
    - `extent` : étendue sur laquelle on veut calculer la pyramide, soit un rectangle englobant (de la forme `xmin,ymin,xmax,ymax`), soit le chemin vers un fichier contenant une géométrie WKT, GeoJSON ou GML
    - `srs` : projection de l'étendue fournie, ainsi que celle des données en base
    - `db`
        - `host` : hôte du serveur PostgreSQL contenant la base de données
        - `port` : port d'écoute du serveur PostgreSQL contenant la base de données. 5432 par défaut
        - `database` : nom de la base de données
        - `user` : utilisateur PostgreSQL
        - `password` : mot de passe de l'utilisateur PostgreSQL
    - `tables`
        - `schema` : nom du schéma contenant la table
        - `native_name` : nom en base de la table
        - `final_name` : nom dans les tuiles vecteur finale de la pyramide de cette table. Est égal au nom natif si non fourni.
        - `attributes` : attribut à exporter dans les tuiles vecteur de la pyramide. Une chaîne vide ou absent pour n'exporter que la géométrie, "\*" tous les exporter.
        - `filter` : filtre attributaire (optionnel)

### Exemple

```json
{
    "10":{
        "srs": "EPSG:3857",
        "extent": "/home/IGN/FXX.wkt",
        "db": {
            "host": "postgis.ign.fr",
            "port": "5433",
            "database": "geobase",
            "user": "ign",
            "password": "pwd"
        },
        "tables": [
            {
                "schema": "bdcarto",
                "native_name": "limites_administratives",
                "filter" : "genre = 'Limite de département'"
            }
        ]
    },
    "15":{
        "srs": "EPSG:3857",
        "tippecanoe_options": "-al -ap",
        "extent": "/home/IGN/D008.wkt",
        "db": {
            "host": "postgis.ign.fr",
            "port": "5433",
            "database": "geobase",
            "user": "ign",
            "password": "pwd"
        },
        "tables": [
            {
                "schema": "bdtopo",
                "native_name": "limites_administratives"
            },
            {
                "schema": "bdtopo",
                "native_name": "routes",
                "final_name": "roads",
                "attributes": "nom",
                "filter": "importance = '10'"
            }
        ]
    },
    "18":{
        "srs": "EPSG:3857",
        "extent": "/home/IGN/D008.wkt",
        "db": {
            "host": "postgis.ign.fr",
            "port": "5433",
            "database": "geobase",
            "user": "ign",
            "password": "pwd"
        },
        "tables": [
            {
                "schema": "bdtopo",
                "native_name": "limites_administratives",
                "attributes": "nom"
            },
            {
                "schema": "bdtopo",
                "native_name": "routes",
                "final_name": "roads",
                "attributes": "*"
            }
        ]
    }
}
```

## Résumé des fichiers et dossiers manipulés

Avec les configurations mises en exemple :

* La configuration principale `/home/IGN/conf.txt`
* La configuration d'environnement `/home/IGN/env.txt`
* La configuration de la source de données `/home/ign/SOURCE/sources.json`
* Le TMS `/home/IGN/TMS/PM.json`
* Le fichier de logs `/var/log/4alamo_2019-02-01.txt`
* Les scripts :
    - `/home/IGN/SCRIPT/SCRIPT_1.sh`, `/home/IGN/SCRIPT/SCRIPT_2.sh`, `/home/IGN/SCRIPT/SCRIPT_3.sh`, `/home/IGN/SCRIPT/SCRIPT_4.sh`, exécutables en parallèle et sur des machines différentes. Les exécutables externes au projet ROK4 `tippecanoe` et `ogr2ogr` doivent être présents sur ces machines.
    - `/home/IGN/SCRIPT/SCRIPT_FINISHER.sh`, à exécuter quand tous les splits sont terminés en succès.
* Le dossier temporaire commun `/mnt/share/`
* Les dossiers temporaires propres à chaque script `/tmp/SCRIPT_1/`, `/tmp/SCRIPT_2/`, `/tmp/SCRIPT_3/`, `/tmp/SCRIPT_4/`
* Le dossier contenant les données de la pyramide `/home/IGN/PYRAMIDS/BDTOPO/`
* Le descripteur de pyramide `/home/IGN/PYRAMIDS/BDTOPO.pyr`
* La liste des dalles `/home/IGN/PYRAMIDS/BDTOPO.list`.
