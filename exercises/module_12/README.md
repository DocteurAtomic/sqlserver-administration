# Exercice du module 12

Objectif : écrire et vérifier la stratégie de sauvegarde d'une seconde base, avec
`DatabaseBackup` d'Ola Hallengren. La base de l'exercice, `PachadataTraining_Ex12`, tient lieu
de la plateforme d'e-learning de PachaData. Son responsable accepte de perdre une heure de
progression des stagiaires au plus, veut la base rendue en moins de trente minutes, et
demande trois jours de fichiers sur le disque.

L'exercice se joue sur votre labo, dans une seule session. Il n'écrit jamais dans
`PachadataTraining` : il travaille sur une copie, que le corrigé supprime à la fin, avec tout
ce qu'il a créé sur l'instance (un certificat dans `master`, un travail de l'Agent, les
fichiers de sauvegarde et leur historique).

## Avant de commencer

`DatabaseBackup` doit être installée dans la base `DBA` du labo : `setup/install.sh` l'y a
mise. Si elle manque, lancez une fois, depuis la racine du dépôt :

```bash
./setup/install-ola.sh
```

## Les fichiers

- `1-start.sql` restaure la copie `PachadataTraining_Ex12` (mode de récupération `SIMPLE`) et
  crée le répertoire racine de ses sauvegardes, `/var/opt/mssql/backup/exercise_12`. La charge
  de l'exercice est la table `Elearning.Progress`, 251 965 lignes de progression.
- `2-solution.sql` est le corrigé, à lire après avoir cherché. Il dure moins d'une minute et
  nettoie ce qu'il crée. Les dossiers vides et les deux fichiers du certificat restent : le
  T-SQL ne les supprime pas.

```bash
docker exec -i sqladmcourse /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C < exercises/module_12/1-start.sql
docker exec sqladmcourse rm -rf /var/opt/mssql/backup/exercise_12   # à la toute fin
```

## Partie 1. Le mode de récupération

1. Passez la base en mode `FULL`. Lisez `last_log_backup_lsn` dans
   `sys.database_recovery_status`. Que répondrait `BACKUP LOG` à cet instant ?
2. Écrivez du journal sans changer les données : deux `UPDATE` de toute la table
   `Elearning.Progress`, `TimeSpentSeconds + 1` puis `TimeSpentSeconds - 1`. Faites un
   `CHECKPOINT`, et mesurez l'espace utilisé du journal (`sys.dm_db_log_space_usage`) et
   `log_reuse_wait_desc`.

## Partie 2. Complète, différentielle, journal

1. Dans `DBA`, prenez la première sauvegarde complète par `dbo.DatabaseBackup` :
   `@Directory` sur le répertoire de l'exercice, `@Verify`, `@Checksum`, compression `ZSTD` au
   niveau `MEDIUM` (`@CompressionLevel`), et une rétention qui répond à la demande
   (`@CleanupTime`, en heures).
2. Refaites la charge et le `CHECKPOINT` de la partie 1. Que deviennent l'espace utilisé et
   `log_reuse_wait_desc` ?
3. Prenez une différentielle, puis une sauvegarde du journal, avec les mêmes options.
   Mesurez de nouveau l'espace utilisé du journal.
4. Lisez dans `dbo.CommandLog` ce que la procédure a exécuté pour chaque appel.
5. Lisez la chaîne dans `msdb.dbo.backupset`, filtrée sur `server_name = @@SERVERNAME` :
   `first_lsn`, `last_lsn`, `checkpoint_lsn`, `differential_base_lsn`. De quelle sauvegarde la
   différentielle part-elle ? Où commence la sauvegarde du journal, et pourquoi pas après la
   complète ?

## Partie 3. Deux fichiers

1. Prenez une sauvegarde complète en copie seule, répartie sur deux fichiers
   (`@CopyOnly`, `@NumberOfFiles`). Dans quel répertoire arrive-t-elle ?
2. Lisez `RESTORE LABELONLY` sur le premier des deux fichiers. Que faudrait-il présenter à
   une restauration ?

## Partie 4. Une sauvegarde chiffrée

1. Créez dans `master` un certificat `ExerciseCert12`, avec une date d'expiration (et la clé
   principale de base de données de `master` si elle manque). Sauvegardez-le aussitôt, avec sa clé privée, dans le
   répertoire de l'exercice.
2. Prenez une sauvegarde complète en copie seule, chiffrée en `AES_256` par ce certificat,
   avec les paramètres de `DatabaseBackup` faits pour cela (`@Encrypt`,
   `@EncryptionAlgorithm`, `@ServerCertificate`). Vérifiez dans `msdb` l'algorithme et le
   type de chiffreur.

## Partie 5. La planification et la preuve

1. Créez un travail de l'Agent d'une étape T-SQL, exécutée dans `DBA`, qui sauvegarde le
   journal de la base par `DatabaseBackup`, avec une planification qui répond au RPO.
2. Lancez-le à la main (`sp_start_job`) et lisez son historique.
3. Écrivez la requête qui prouve que la demande est satisfaite : le mode de la base, l'âge de
   sa dernière sauvegarde du journal, l'intervalle de la planification.

## Les questions

- Pourquoi la base en mode `FULL` se comporte-t-elle comme en `SIMPLE` à la partie 1, et
  jusqu'à quand ?
- La première complète de `DatabaseBackup` dit « Modified extent page count » de 181 632
  pages, presque toute la base. Pourquoi, sur une base qui sort d'une restauration ?
- Une différentielle prise toutes les combien de temps tient-elle le RTO de trente minutes,
  sachant qu'une restauration rejoue la complète, la dernière différentielle et les
  sauvegardes du journal qui suivent ? Mesurez la durée de votre complète pour en juger.
- Que se passerait-il, pour les différentielles, si les sauvegardes des parties 3 et 4
  n'étaient pas en copie seule ?
- Que faut-il, en plus du fichier de sauvegarde chiffré, pour restaurer sur un autre serveur ?
  Où ranger le fichier `.pvk` et son mot de passe ?
- Le travail de la partie 5 tourne sous quel compte, sur le labo Linux ?
