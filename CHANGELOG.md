## 5.0.0

### [Changed]

* `be4` : 
    * on ne précise plus de nodata dans le cas d'application d'un style (ce dernier en contient déjà un)
    * on compare les sample format avec la nouvelle version
* `joincache` : 
    * on utilise les sample formats avec la nouvelle version (qui contient le nombre de bits)

### [Added]

* `4alamo` :
    * on limite la récupération des statistiques sur les attributs à la zone de calcul
    * on n'extraie les données que sur l'intersetion de la dalle et de la zone de calcul
    * on force les gémétries en 2 dimensions
    * si aucune donnée dans la sous pyramide à calculer, on passe à la suite
    * on force la multi géométrie si les deux sont présents
    * on applique une validation sur les géométries lors de l'export

## 4.2.6

### [Changed]

* `JOINCACHE` : 
  * L'écriture d'objet symbolique en S3 se fait avec un retry (ROK4_OBJECT_WRITE_ATTEMPTS (0) fois, ROK4_OBJECT_ATTEMPTS_WAIT (2) secondes entre chaque tentative)

## 4.2.5

### [Fixed]

* `4ALAMO` : 
  * Correction de la sortie en erreur lors de l'appel à tippecanoe

## 4.2.4

### [Changed]

* `JOINCACHE` : Passage en silencieux des curl pour créer des objets symboliques.

## 4.2.3

### [Fixed]

* `4ALAMO` : pour permettre la génération de pyramide vecteur avec des données dont des attributs sont du vocabulaire SQL, on doit quoter correctement leurs noms.

## 4.2.2

### [Fixed]

* BE4
  * On précise à mergeNtiff que la première image en entrée est une image de fond.


<!-- 
### [Added]

### [Changed]

### [Deprecated]

### [Removed]

### [Fixed]

### [Security] 
-->
