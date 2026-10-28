# Exercice du module 13

Objectif : retrouver une erreur dans une chaîne de sauvegardes, la réparer sans perdre le
travail fait depuis, puis perdre le fichier de données de la base et la rendre sans perdre la
réparation. La base de l'exercice, `PachadataTraining_Ex13`, tient lieu de la facturation des
formateurs. Quelqu'un a voulu augmenter de 10 % le tarif journalier de tous les engagements
(`Trainer.Engagement.DailyRate`) et a tapé `* 0.10` au lieu de `* 1.10`, sans `WHERE`, dans une
transaction marquée. Il ne sait plus quand.

L'exercice se joue sur votre labo, dans une seule session. Il n'écrit jamais dans
`PachadataTraining` : il travaille sur une copie, que le corrigé supprime à la fin, avec ses
fichiers de sauvegarde et leur historique. Il ne crée rien d'autre sur l'instance.

## Les fichiers

- `1-start.sql` restaure la copie `PachadataTraining_Ex13`, la passe en mode `FULL` et prend
  dans `/var/opt/mssql/backup/exercise_13` une complète et trois sauvegardes du journal,
  quelques secondes d'écart. Entre deux d'entre elles, à un moment tiré au hasard, l'erreur ;
  après elle, un engagement neuf (`InvoiceNumber` `EX13-NEW`) et d'autres modifications. La
  table `dbo.ExClock` reçoit une ligne avant chaque sauvegarde. Il dure moins d'une minute.
- `2-solution.sql` est le corrigé des parties 1 à 3, à lire après avoir cherché. Il trouve
  l'erreur comme vous la chercherez, sans savoir où le hasard l'a mise.
- `3-solution-file-loss.sql` est le corrigé de la partie 4, en deux morceaux séparés par la
  suppression du fichier. Il supprime la copie et ses sauvegardes à la fin.

```bash
docker exec -i sqladmcourse /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C < exercises/module_13/1-start.sql
docker exec sqladmcourse rm -rf /var/opt/mssql/backup/exercise_13   # à la toute fin
```

## Partie 1. La chaîne

1. Lisez la chaîne de `PachadataTraining_Ex13` dans `msdb.dbo.backupset`, jointe à
   `backupmediafamily`, filtrée sur `server_name = @@SERVERNAME` : type, `first_lsn`,
   `last_lsn`, `last_valid_restore_time`, fichier.

## Partie 2. Trouver l'erreur

1. Restaurez la complète sous le nom `PachadataTraining_Ex13_Read`, fichiers déplacés par
   `MOVE` dans `/var/opt/mssql/data`, avec `STANDBY` et un fichier d'annulation dans le
   répertoire de l'exercice.
2. Lisez la moyenne de `DailyRate` et la dernière ligne de `dbo.ExClock`. Appliquez les
   sauvegardes du journal une par une, toujours avec `STANDBY`, en relisant après chacune.
   Dans quel journal est l'erreur ?
3. Terminez la séquence par `RESTORE DATABASE ... WITH RECOVERY`, puis supprimez la copie.
4. Lisez `msdb.dbo.logmarkhistory` : nom de la marque, description, heure, LSN.

## Partie 3. Réparer

1. Restaurez sous le nom `PachadataTraining_Ex13_PIT` la complète et les journaux en
   `NORECOVERY`, jusqu'au journal qui contient la marque, restauré avec `STOPBEFOREMARK` et
   `RECOVERY`.
2. Comparez les deux bases : nombre d'engagements, tarif maximal.
3. Remettez dans `PachadataTraining_Ex13` les tarifs de la copie, et rien d'autre. Vérifiez que
   l'engagement `EX13-NEW` et les frais de déplacement modifiés après l'erreur sont toujours là.
4. Supprimez la copie et son historique de restauration.

## Partie 4. Le fichier de données perdu

1. Relevez la moyenne et le maximum de `DailyRate`. Mettez `PachadataTraining_Ex13` hors ligne.
2. Supprimez son fichier de données, et lui seul :
   `docker exec sqladmcourse rm /var/opt/mssql/data/PachadataTraining_Ex13.mdf`.
3. Remettez la base en ligne. Lisez les erreurs et son état dans `sys.databases`.
4. Sauvegardez la fin de son journal, puis restaurez-la en place, sous son nom, avec les seules
   sauvegardes nécessaires.
5. Relisez la moyenne et le maximum de `DailyRate`.
6. Supprimez la copie, ses fichiers de sauvegarde et leur historique.

## Les questions

- Pourquoi la copie de la partie 2 se lit-elle entre deux journaux ? Que contient le fichier
  `.tuf`, et que devient-il après `WITH RECOVERY` ?
- Que se passe-t-il si vous sautez un journal de la chaîne ?
- Quelle différence entre `STOPBEFOREMARK` et `STOPATMARK` sur cette erreur ? Qu'auriez-vous
  dû savoir pour faire la même chose avec `STOPAT` ?
- Pourquoi restaurer à côté plutôt qu'en place, par-dessus `PachadataTraining_Ex13` ?
- Pourquoi la réparation est-elle un `UPDATE` joint et non un `INSERT ... SELECT` comme dans la
  vidéo ? Qu'aurait perdu un remplacement de toute la table ?
- À la partie 4, quelle sauvegarde contient la réparation de la partie 3 ? Que serait-il arrivé
  si vous aviez supprimé la base pour la restaurer, au lieu de sauvegarder d'abord la fin de
  son journal ?
- Pourquoi la restauration de la partie 4 n'a-t-elle demandé ni `MOVE` ni `REPLACE` ?
