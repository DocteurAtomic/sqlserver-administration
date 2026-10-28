# Exercice du module 4

Objectif : créer et dimensionner une base d'archives, en suivre le journal, la réduire sans
abîmer ses index, et corriger les options d'une base mal tenue. L'équipe marketing de
PachaData veut sortir de la base de production les e-mails de ses campagnes déjà envoyés,
dans une base à elle, `MarketingArchive_Ex04`. Elle vous confie aussi une copie d'une base
reprise d'un ancien serveur, `PachadataTraining_Ex04`, dont personne n'a relu les options.

L'exercice se joue sur votre labo, dans une session (deux fenêtres de requête pour la
partie 3). Il n'écrit jamais dans `PachadataTraining`, qu'il lit seulement : il crée sa propre
base et restaure une copie, que le corrigé supprime toutes deux à la fin.

## Les fichiers

- `1-start.sql` supprime `MarketingArchive_Ex04` si un essai précédent l'a laissée, restaure
  la copie `PachadataTraining_Ex04` et lui donne les options d'une base mal tenue. Il affiche
  le nombre d'e-mails par année dans `Marketing.Delivery`, la table que vous archivez.
- `2-solution.sql` est le corrigé, à lire après avoir cherché. Il dure moins d'une minute et
  supprime les deux bases de l'exercice.

```bash
docker exec -i sqladmcourse /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C < exercises/module_04/1-start.sql
```

## Partie 1. Une base à deux groupes de fichiers

1. Créez la base `MarketingArchive_Ex04` :
   - un groupe `PRIMARY` d'un fichier `MarketingArchive_Ex04_sys` de 16 Mo, croissance de
     16 Mo ;
   - un groupe `DELIVERY`, groupe par défaut, de deux fichiers `MarketingArchive_Ex04_d1` et
     `MarketingArchive_Ex04_d2` de 64 Mo, croissance de 64 Mo ;
   - un journal `MarketingArchive_Ex04_log` de 8 Mo, avec une croissance de 1 Mo, comme on en
     trouve sur des bases anciennes ;
   - le mode de récupération `SIMPLE`.
2. Créez une table `dbo.Delivery` sans clause `ON`, avec les colonnes de
   `PachadataTraining.Marketing.Delivery` et une clé primaire en index cluster sur
   `DeliveryId`. Chargez-y les e-mails de 2023 et 2024, en une seule instruction.
3. Retrouvez dans `sys.indexes` et `sys.data_spaces` le groupe de fichiers de la table.
   Mesurez l'espace utilisé de chaque fichier de données.
4. Ajoutez au groupe `DELIVERY` un troisième fichier de 128 Mo. Chargez les e-mails de 2025,
   et refaites la mesure.

## Partie 2. Le journal et ses VLF

1. Comptez les croissances automatiques du journal depuis la création de la base, dans la
   trace par défaut (`sys.traces`, `is_default = 1`, événement 93). Comptez les VLF dans
   `sys.dm_db_log_info`, et relevez la taille du journal.
2. Posez pour votre session les indicateurs de trace 3004 et 3605, faites grandir le journal
   à la main de 64 Mo exactement, retirez les indicateurs. Comptez les VLF ajoutés, et
   cherchez la mise à zéro dans le journal d'erreurs (`sys.xp_readerrorlog` avec `Zeroing`).

## Partie 3. Une transaction ouverte

1. Dans une première fenêtre, ouvrez une transaction et modifiez toutes les lignes de 2023
   et 2024 (`CampaignId + 1`), sans la valider.
2. Dans une seconde fenêtre, positionnée sur la base, lancez `CHECKPOINT`, puis lisez
   `log_reuse_wait_desc`, la taille du journal et son remplissage
   (`sys.dm_db_log_space_usage`).
3. Annulez la transaction dans la première fenêtre, relancez `CHECKPOINT` et la mesure.
4. Réduisez le journal au minimum (`DBCC SHRINKFILE`), puis reportez-le en une opération à
   256 Mo, avec une croissance de 128 Mo. Comptez les VLF à chaque étape.

## Partie 4. L'ordre des opérations

1. Supprimez les e-mails de 2023 et 2024.
2. Reconstruisez l'index cluster de `dbo.Delivery` (`REBUILD`), puis mesurez la taille et
   l'espace utilisé des fichiers, et la fragmentation de l'index
   (`sys.dm_db_index_physical_stats`, mode `LIMITED`).
3. Réduisez chacun des trois fichiers du groupe `DELIVERY` à 32 Mo, avec
   `WAIT_AT_LOW_PRIORITY (ABORT_AFTER_WAIT = SELF)`. Refaites les deux mesures.
4. Remettez l'index en ordre sans faire regrandir les fichiers, et refaites les deux mesures.

## Partie 5. Les options de toutes les bases

1. Écrivez la requête qui donne, pour chaque base utilisateur, le propriétaire, les options
   `AUTO_CLOSE`, `AUTO_SHRINK`, `PAGE_VERIFY`, les deux options de statistiques automatiques
   et la collation, lue dans `sys.databases` et par `DATABASEPROPERTYEX`.
2. Écrivez la requête qui génère, pour chaque base qui s'écarte des recommandations, le
   `ALTER DATABASE` qui la corrige, avec les seules options en écart. Relisez le texte.
3. Appliquez la correction à `PachadataTraining_Ex04` seulement, donnez-lui `sa` pour
   propriétaire, et relisez ses options.

## Les questions

- Combien de mégaoctets chaque fichier a-t-il reçus au premier chargement, et au second ?
  Quelle règle relie ce que reçoit un fichier à son état avant le chargement ? Les pages de
  `d1` et `d2` ont-elles été déplacées vers `d3` ?
- Combien de croissances le journal a-t-il subies, et combien de VLF compte-t-il ? Pourquoi,
  au-delà de 8 Mo, une croissance de 1 Mo n'ajoute-t-elle qu'un VLF ?
- Learn annonce depuis SQL Server 2022 qu'une croissance de 64 Mo au plus ne crée qu'un VLF,
  et qu'une croissance automatique du journal jusqu'à 64 Mo n'est pas mise à zéro. Que
  montre votre labo ?
- Pourquoi le journal est-il rempli presque entièrement pendant la transaction ouverte, et
  pourquoi le fichier garde-t-il sa taille après la troncature ?
- Pourquoi reporter le journal à sa taille de travail en une opération, plutôt que le laisser
  regrandir ?
- Que devient la fragmentation après la réduction, et pourquoi ? Pourquoi avoir choisi
  `REORGANIZE` plutôt qu'un second `REBUILD` pour la corriger ?
- Pourquoi la collation de la copie est-elle `NULL` avant la correction, et qu'en conclurait
  un script de surveillance ? Après `PAGE_VERIFY CHECKSUM`, les pages existantes sont-elles
  protégées par une somme de contrôle ?
