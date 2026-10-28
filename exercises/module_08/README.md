# Exercice du module 8

Objectif : chiffrer une colonne sensible d'une seconde base, la chiffrer par TDE, et prouver
qu'une sauvegarde de cette base ne se restaure sur une autre instance qu'avec le certificat et
le mot de passe de la clé principale de la base. La base de l'exercice,
`PachadataContacts_Ex08`, tient lieu du fichier de contacts du service commercial : les
adresses électroniques des contacts ne doivent plus être lisibles par le compte de l'outil de
publipostage, `MailingTool`, qui doit pourtant pouvoir retrouver un contact par son adresse.

L'exercice se joue sur votre labo et sur la seconde instance du module, `sqladm-08b`. Il
n'écrit jamais dans `PachadataTraining`, qu'il ne fait que lire : `1-start.sql` crée la base
de l'exercice.

## Avant de commencer

La seconde instance se crée par le script des démonstrations, depuis la racine du dépôt
(avec Podman, préfixez par `ENGINE=podman`) :

```bash
./demos/module_08/01b-second-instance.sh create
```

Elle écoute sur `localhost,14434`, avec le mot de passe `sa` du labo.

## Les fichiers

- `1-start.sql` crée `PachadataContacts_Ex08` : une copie de `Contact.Contact`
  (`ContactId`, `LastName`, `FirstName`, `Email`, 120 140 lignes, dont 107 994 avec une
  adresse), et l'utilisateur `MailingTool`, sans connexion, qui lit la table. Il crée aussi le
  répertoire `/var/opt/mssql/backup/exercise_08`.
- `2-solution-column.sql`, `3-solution-tde-source.sql` et `4-solution-tde-target.sql` sont le
  corrigé, en trois temps, à lire après avoir cherché. Le troisième se joue sur la seconde
  instance.
- `5-cleanup.sql` supprime ce que l'exercice a créé sur le labo.

```bash
docker exec -i sqladmcourse /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C < exercises/module_08/1-start.sql
```

## Partie 1. La colonne chiffrée

1. Créez la clé principale de la base (gardez son mot de passe : la partie 4 en a besoin), un
   certificat `EmailCert` avec une date d'expiration, et une clé symétrique `EmailKey` en
   `AES_256`, protégée par le certificat. Vérifiez `is_master_key_encrypted_by_server` dans
   `sys.databases`.
2. Ajoutez une colonne `EmailEncrypted` et chiffrez-y les adresses. Quelle taille prend une
   adresse chiffrée, au plus, contre sa taille en clair ? Comment déclarer la colonne ?

## Partie 2. Le compte de publipostage et la recherche

1. Sous l'identité de `MailingTool` (`EXECUTE AS USER`), lisez la colonne chiffrée, puis
   essayez de la déchiffrer par `DECRYPTBYKEYAUTOCERT`. Que rend-elle ?
2. Ajoutez une colonne d'empreinte qui permette de retrouver un contact par son adresse, même
   tapée avec des majuscules, et indexez-la. Retrouvez le contact de `J.Garcia@100dayloans.com`
   et lisez le nombre de lectures logiques.
3. Supprimez la colonne `Email` en clair, et affichez l'adresse de ce contact en la
   déchiffrant.

## Partie 3. TDE sur le labo

1. Dans `master`, créez un certificat `ExerciseTdeCert08` (et la clé principale de `master` si
   elle manque). Lisez `pvt_key_last_backup_date`, puis sauvegardez le certificat avec sa clé
   privée dans `/var/opt/mssql/backup/exercise_08`.
2. Chiffrez `PachadataContacts_Ex08` par TDE et suivez l'analyse TDE jusqu'à `ENCRYPTED`. Quelles
   bases montre `sys.dm_database_encryption_keys` ?
3. Prenez une sauvegarde complète en copie seule, compressée, dans le même répertoire.
4. Copiez le répertoire sur la seconde instance :

   ```bash
   ./demos/module_08/01b-second-instance.sh copy exercise_08
   ```

## Partie 4. La restauration sur la seconde instance

1. Connecté à `localhost,14434`, lisez la liste des fichiers de la sauvegarde
   (`RESTORE FILELISTONLY`). Que répond l'instance ?
2. Faites ce qu'il faut pour restaurer la base, puis restaurez-la.
3. Comptez les adresses déchiffrées. Pourquoi aucune ? Réparez, et retrouvez l'adresse de
   `J.Garcia@100dayloans.com` par son empreinte.
4. Nettoyez la seconde instance : la base, le certificat, la clé principale de `master`.

## Le nettoyage

Sur le labo, `5-cleanup.sql` supprime la base, la sauvegarde et son historique, le certificat
et la clé principale de `master` si plus rien ne s'en sert. Le T-SQL ne supprime ni les fichiers du
certificat ni le chiffrement de `tempdb`, qui dure jusqu'au redémarrage de l'instance. Puis, dans
un terminal :

```bash
docker exec sqladmcourse rm -rf /var/opt/mssql/backup/exercise_08
docker exec -i sqladmcourse /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -Q "SHUTDOWN"
docker start sqladmcourse
./demos/module_08/01b-second-instance.sh remove
```

## À réfléchir

- Pourquoi l'empreinte se calcule-t-elle sur l'adresse en minuscules ? Que se passerait-il
  sans le préfixe secret, sur une donnée comme une adresse électronique ?
- `MailingTool` reçoit `NULL` sans message d'erreur. Qu'en conclurait une application mal
  écrite ?
- La sauvegarde chiffrée par TDE fait-elle la même taille que si la base était en clair ?
- Dans la partie 4, quel fichier ou quel mot de passe vous aurait manqué si vous ne l'aviez
  pas gardé, et qu'auriez-vous perdu dans chaque cas ?
- Après `5-cleanup.sql`, pourquoi `tempdb` est-elle encore chiffrée sur le labo ?
