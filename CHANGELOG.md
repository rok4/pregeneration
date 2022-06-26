# Outils de pré-génération ROK4

## Summary

Le projet ROK4 a été totalement refondu, dans son organisation et sa mise à disposition. Les composants sont désormais disponibles dans des releases sur GitHub au format debian.

Cette release contient les outils de prégénération des pyramides de données, écrivant les scripts de génération.

## Changelog

### [Added]

* Les outils sont capables de lire les descripteurs directement sur les stockages objets
* 4ALAMO peut générer une pyramide de tuiles vectorielles directement à partir de fichier GeoJSON ou CSV
* Possibilité de fournir les options TIPPECANOE à appliquer dans 4ALAMO
* Possibilité de préciser des styles à appliquer aux données raster dans BE4
* BE4, 4ALAMO et JOINCACHE peuvent écrire des pyramides faisant référence à des pyramides dans d'autres contenants dans le cas d'un stockage objet
* PYR2PYR sait lire les anciennes pyramides (descripteur et organisation de données) pour les convertir au nouveau format

### [Changed]

* Les configurations des outils sont en JSON, dont les spécifications sont décrites sous forme de schémas JSON
* BE4 n'a plus qu'une seule configuration, contenant toutes les informations
* Les chemins sont fournis dans un format précisant le type de stockage : `(file|ceph|s3|swift)://<chemin vers le fichier ou l'objet>`. Dans le cas du stockage objet, le chemin est de la forme `<nom du contenant>/<nom de l'objet>`

### [Removed]

* Suppression de l'outil WMTSALAD : l'exposition d'une pyramide selon un TMS non natif est géré directement au niveau du serveur de diffusion

<!-- 
### [Added]

### [Changed]

### [Deprecated]

### [Removed]

### [Fixed]

### [Security] 
-->