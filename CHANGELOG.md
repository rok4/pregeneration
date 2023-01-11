# Outils de pré-génération ROK4

## Summary

Le projet ROK4 a été totalement refondu, dans son organisation et sa mise à disposition. Les composants sont désormais disponibles dans des releases sur GitHub au format debian.

Cette release contient les outils de prégénération des pyramides de données, écrivant les scripts de génération.

## Changelog

### [Added]

* Gestion des redirections par Curl pour les requêtes de téléversement de fichier sur un stockage objet SWIFT ou S3
* Fourniture du filtre des données lors des demandes de statistiques sur les données en base postgresql
* BE4 : génération d'une valeur de nodata par défaut si non fournie (basée sur le format de pixel en sortie)

### [Fixed]

* Correction du schéma JSON de description du fichier de configuration de l'outil PYR2PYR

<!-- 
### [Added]

### [Changed]

### [Deprecated]

### [Removed]

### [Fixed]

### [Security] 
-->