## 4.2.6

### [Changed]

* `JOINCACHE` : 
  * L'écriture d'objet symbolique en S3 se fait avec un retry (5 fois, 2 secondes entre chaque tentative)

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
