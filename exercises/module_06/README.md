# Exercice du module 6

Objectif : protéger une opération risquée par un instantané, récupérer une table sans faire
revenir toute la base, mesurer la journalisation d'une copie de table, puis exporter et
recharger une table sans rien perdre. La base de l'exercice, `PachadataTraining_Ex06`, tient
lieu de la plateforme d'e-learning et de la caisse de PachaData. L'équipe e-learning veut
purger les progressions de plus de six ans, et la comptabilité veut les paiements dans des
fichiers.

L'exercice se joue sur votre labo, dans une session SSMS et un terminal. Il n'écrit jamais
dans `PachadataTraining` : il travaille sur une copie, que le corrigé supprime à la fin.

## Les fichiers

- `1-start.sql` supprime les instantanés qu'un essai précédent aurait laissés sur la copie,
  restaure la copie `PachadataTraining_Ex06` et crée le répertoire d'échange de l'exercice,
  `/var/opt/mssql/exchange/exercise_06`. Il affiche le nombre de lignes des trois tables de
  l'exercice.
- `2-solution.sql` est le corrigé des parties 1 et 2, à lire après avoir cherché. Il dure
  moins d'une minute et garde la copie pour la partie 3.
- `3-solution-export.sh` est le corrigé des commandes `bcp` de la partie 3, à lancer depuis la
  racine du dépôt (avec Podman : `ENGINE=podman`).
- `4-solution-load.sql` est le corrigé T-SQL de la partie 3. Il supprime la copie à la fin.

```bash
docker exec -i sqladmcourse /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C < exercises/module_06/1-start.sql
docker exec sqladmcourse rm -rf /var/opt/mssql/exchange/exercise_06   # à la toute fin
```

## Partie 1. L'instantané

1. Créez l'instantané `PachadataTraining_Ex06_BeforePurge` de la copie, son fichier `.ss` dans
   `/var/opt/mssql/data`. Lisez dans `sys.master_files` et `sys.dm_io_virtual_file_stats` :
   `is_sparse`, la taille maximale, `size_on_disk_bytes` et `num_of_bytes_written`.
2. La purge de l'équipe e-learning : supprimez de `Elearning.Progress` les lignes dont
   `LastActivity` est antérieure au 1er janvier 2020. Comparez le nombre de lignes dans la base
   et dans l'instantané.
3. Relisez ce que l'instantané a reçu, et comparez-le à la taille de la table avant la purge
   (`sys.dm_db_partition_stats`, lue dans l'instantané).
4. Créez un second instantané, `PachadataTraining_Ex06_Second`, puis tentez de faire revenir
   la copie à l'état de `PachadataTraining_Ex06_BeforePurge`. Notez l'erreur. Supprimez le
   second instantané et recommencez. Aucune autre fenêtre ne doit être positionnée sur la
   copie.
5. Relisez le nombre de lignes de `Elearning.Progress`, puis la taille et la croissance des
   fichiers de la copie dans `sys.master_files`. Redonnez au journal 1 200 Mo et une
   croissance de 50 Mo.
6. Supprimez `PachadataTraining_Ex06_BeforePurge` et créez un instantané
   `PachadataTraining_Ex06_Rescue`. Dans la copie, ajoutez 60 secondes à `TimeSpentSeconds`
   pour les progressions de 2026, puis supprimez par erreur la table `Enrollment.Answer`.
   Récupérez la table depuis l'instantané, sans retour arrière, et vérifiez que la
   modification des progressions a survécu. Comparez les index de la table récupérée à ceux
   de l'instantané.
7. Supprimez l'instantané.

## Partie 2. La journalisation d'une copie de table

1. Écrivez une procédure qui recrée un tas vide `dbo.ProgressCopy` avec les colonnes de
   `Elearning.Progress`, fait un `CHECKPOINT`, puis, dans une transaction, le remplit par
   `INSERT ... SELECT`, avec ou sans `WITH (TABLOCK)` selon un paramètre, et rend le nombre
   d'enregistrements et les kilo-octets de journal écrits par la transaction
   (`sys.dm_tran_database_transactions`).
2. Une seconde procédure fait la même mesure pour `SELECT ... INTO`.
3. Mesurez en mode `SIMPLE` : `INSERT` sans puis avec `TABLOCK`, puis `SELECT ... INTO`.
4. Passez la copie en `BULK_LOGGED`, et mesurez `INSERT` avec `TABLOCK` et `SELECT ... INTO`.
5. Passez-la en `FULL`, sans faire de sauvegarde, et refaites ces deux mesures.
6. Remettez la copie en `SIMPLE` et supprimez la table et les procédures.

## Partie 3. Exporter et recharger les paiements

1. Avant de choisir un séparateur, comptez les paiements dont une colonne de texte contient
   une virgule, un point-virgule ou une tabulation.
2. En ligne de commande, depuis le répertoire d'échange de l'exercice, dans le conteneur :
   1. exportez en natif, par `queryout`, les paiements depuis le 1er janvier 2020, dans
      `payment.bcp` ;
   2. créez deux tables vides de la structure de `Enrollment.Payment`, `dbo.PaymentNative` et
      `dbo.PaymentNativeKeep` (`SELECT TOP (0) ... INTO`) ;
   3. rechargez `payment.bcp` dans la première par `bcp in` avec l'indication `TABLOCK`, puis
      dans la seconde avec en plus l'option `-E` ;
   4. exportez toute la table en texte avec le séparateur choisi, dans `payment.csv`, et
      générez son fichier de format, `payment.fmt`.
3. Comparez par `EXCEPT` chacune des deux tables aux paiements depuis 2020. Comparez les
   `PaymentId` minimaux et maximaux.
4. Chargez `payment.csv` dans une table vide `dbo.PaymentCsv` par `BULK INSERT`, en gardant
   les valeurs d'identité, et vérifiez par `EXCEPT` dans les deux sens. Que sont devenus les
   numéros de chèque absents ?
5. Par `OPENROWSET(BULK ..., FORMATFILE = ...)`, calculez le nombre et le montant des
   paiements de 2025 lus dans le fichier, et comparez-les à la table.
6. Supprimez la copie.

## Les questions

- Combien de kilo-octets l'instantané a-t-il reçus pour la purge, et pourquoi beaucoup moins
  que la taille de la table ?
- Sous Linux, que vaut `size_on_disk_bytes`, et par quoi le remplacer ?
- Que dit l'erreur du retour arrière avec deux instantanés ? Pourquoi un `TRY ... CATCH`
  n'en montre-t-il qu'une partie ?
- Qu'est devenu le journal de la copie après le retour arrière, et pourquoi le redimensionner
  aussitôt ? Qu'arriverait-il à la chaîne des sauvegardes du journal en mode complet ?
- Qu'est-ce que `SELECT ... INTO` n'a pas récupéré de la table supprimée ?
- `INSERT ... SELECT` et `SELECT ... INTO` suivent-ils les mêmes règles que `BULK INSERT` ?
- Une base en mode complet qui n'a jamais été sauvegardée journalise-t-elle au minimum ?
- Pourquoi, sans `-E`, la comparaison des paiements ne trouve-t-elle aucune ligne commune ?
- Pourquoi `OPENROWSET(BULK)` exige-t-il un fichier de format, et pourquoi convertir ses
  colonnes ?
