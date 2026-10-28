# Exercice du module 3

Objectif : relever les bases système d'une instance, écrire une requête de dernière sauvegarde
qui ne ment pas, sauvegarder les bases système qui doivent l'être, et corriger un conflit de
collation entre une table temporaire et une base. Le responsable de l'exploitation veut ajouter
au registre des serveurs la date de la dernière sauvegarde complète de chaque base.

L'exercice se joue sur votre labo, dans une session. Il n'écrit jamais dans
`PachadataTraining`.

## Les fichiers

- `1-start.sql` restaure une copie de la base, `PachadataTraining_Ex03`, en cinq secondes
  environ.
- `2-solution.sql` est le corrigé, à lire après avoir cherché. Il dure une dizaine de secondes.
  Il supprime à la fin la base `Exercise03_Default`, les trois fichiers de sauvegarde de
  `/var/opt/mssql/backup/exercise_03` et leur historique dans `msdb`, puis la copie. Le dossier
  vide se supprime par `docker exec sqladmcourse rm -r /var/opt/mssql/backup/exercise_03`. Les
  erreurs attendues de la partie 4 y sont attrapées par `TRY ... CATCH`.

```bash
docker exec -i sqladmcourse /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -I < exercises/module_03/1-start.sql
```

## Partie 1. Les bases système

1. Listez les bases système visibles, avec leur mode de récupération, leur niveau de
   compatibilité, leur collation et leur date de création.
2. Relevez la version et la date de mise à jour de `Resource`, et comparez-les à
   `SERVERPROPERTY('ProductVersion')` et à `ProductUpdateLevel`.

## Partie 2. Une base créée sans option

1. Créez une base sans aucune option, `CREATE DATABASE Exercise03_Default;`.
2. Comparez son mode de récupération, sa collation, son Query Store et ses fichiers à ceux de
   `model`.

## Partie 3. La dernière sauvegarde de chaque base

1. Écrivez la requête qui donne, pour chaque base sauf `tempdb`, la date de sa dernière
   sauvegarde complète et de sa dernière sauvegarde du journal, d'après `msdb.dbo.backupset`
   joint à `sys.databases` sur le nom de la base. Que dit-elle de `PachadataTraining` ?
2. Lisez les lignes de `msdb.dbo.backupset` jointes à `msdb.dbo.restorehistory`, et comparez
   `server_name` à `@@SERVERNAME`. D'où vient la ligne ?
3. Sauvegardez `master`, `model` et `msdb` dans `/var/opt/mssql/backup/exercise_03`, avec
   `CHECKSUM`.
4. Corrigez la requête pour qu'elle ne retienne que les sauvegardes faites par cette instance,
   et relancez-la.

## Partie 4. La collation des sociétés clientes

Dans `PachadataTraining_Ex03` :

1. Créez une table temporaire `#Customer (Name varchar(60) NOT NULL)`, remplissez-la avec les
   vingt premières sociétés de `Contact.Company`, et lisez la collation de sa colonne dans
   `tempdb.sys.columns`.
2. Joignez-la à `Contact.Company` sur `Name`. Que répond le moteur ?
3. Corrigez la déclaration de la table temporaire pour que la jointure fonctionne quelle que
   soit la collation de l'instance. Combien de sociétés trouvez-vous ?
4. Créez la table temporaire par `SELECT TOP (20) Name INTO #Copy FROM Contact.Company ...`, et
   lisez la collation de sa colonne.
5. Corrigez la requête d'origine sans toucher à la déclaration de la table temporaire.

## Partie 5. La ligne du registre

Écrivez une requête qui rend, pour chaque base sauf `tempdb`, son mode de récupération, son
propriétaire, sa collation, la date de sa dernière sauvegarde complète prise sur cette
instance, et un avertissement pour une base utilisateur en `FULL` dont le journal n'a jamais été
sauvegardé.

## Les questions

- Pourquoi `model` est-elle en mode `FULL` à l'installation, et que coûte une base créée sans y
  penser dans ce mode ?
- Pourquoi `tempdb` et `Resource` ne se sauvegardent-elles pas ?
- Une sauvegarde de `master` prise aujourd'hui se restaurera-t-elle après la prochaine CU ?
- Qu'en conclurait une supervision qui lirait la requête de dernière sauvegarde sans le filtre
  sur le serveur ?
- Que rendrait la requête filtrée sur un serveur renommé après l'installation, dont
  `@@SERVERNAME` donne encore l'ancien nom ?
- Pourquoi `SELECT ... INTO` ne provoque-t-il pas le conflit de collation ?
- Pourquoi ne pas placer `COLLATE` sur la colonne de la table permanente dans la jointure ?
- `PachadataTraining` contient `Contact.ProspectUS` et `Contact.ProspectUS_SQL_Latin1`. Que
  se passerait-il en les joignant sur `LastName`, et pourquoi la base, ici, n'y est pour rien ?
