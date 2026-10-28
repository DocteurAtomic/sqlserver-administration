# Exercice du module 11

Objectif : vérifier et entretenir une seconde base avec les scripts d'Ola Hallengren, et
planifier sa maintenance. La base de l'exercice, `PachadataTraining_Ex11`, tient lieu de la base
de la comptabilité de PachaData. Sa table `dbo.PaymentArchive`, l'archive des 107 409
paiements, a une page endommagée sur le disque. La responsable de la comptabilité demande que sa
base soit vérifiée et entretenue chaque samedi à 22 h, et veut une preuve que c'est fait.

L'exercice se joue sur votre labo, dans une seule session. Il n'écrit jamais dans
`PachadataTraining` : il travaille sur une copie, que le corrigé supprime à la fin, avec tout ce
qu'il a créé sur l'instance (un travail de l'Agent et sa planification, les lignes de
`DBA.dbo.CommandLog` de la copie).

## Avant de commencer

Les procédures d'Ola Hallengren doivent être installées dans la base `DBA` du labo :
`setup/install.sh` les y a mises. Si elles manquent, lancez une fois, depuis la racine du dépôt :

```bash
./setup/install-ola.sh
```

## Les fichiers

- `1-start.sql` restaure la copie `PachadataTraining_Ex11` (mode `SIMPLE`), y crée
  `dbo.PaymentArchive`, copie de `Enrollment.Payment`, et endommage la page qui contient le
  paiement 50000 par `DBCC WRITEPAGE`, une commande non documentée réservée aux bases de test.
- `2-solution-integrity.sql` est le corrigé de la partie 1. Il finit sur les erreurs attendues de
  `CHECKDB` : ne le lancez pas avec `sqlcmd -b`.
- `3-solution-maintenance.sql` est le corrigé des parties 2 à 4. Il dure un peu plus d'une minute
  et nettoie ce que l'exercice a créé, la copie comprise.

```bash
docker exec -i sqladmcourse /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C < exercises/module_11/1-start.sql
```

## Partie 1. L'intégrité

1. Dans `DBA`, vérifiez la copie par `dbo.DatabaseIntegrityCheck`, avec `@CheckCommands`,
   `@NoInformationalMessages` et `@LogToTable`. Lisez la fin de la sortie.
2. Lisez dans `dbo.CommandLog` la ligne de cette vérification : la commande, la durée,
   `ErrorNumber`, `ErrorMessage`. Lisez `LastGoodCheckDbTime` de la copie.
3. Relevez le nombre de lignes de `dbo.PaymentArchive` sans lire la table.
4. Réparez la copie par `DBCC CHECKDB` avec `REPAIR_ALLOW_DATA_LOSS`. Comptez les lignes, et
   trouvez les paiements perdus en comparant l'archive à `Enrollment.Payment`. Vérifiez de
   nouveau la base, et relisez `LastGoodCheckDbTime`.

## Partie 2. Les index et les statistiques

1. Mesurez la fragmentation et le remplissage des index de plus de 1 000 pages de la copie, en
   mode `SAMPLED`. Listez les statistiques qui ont des modifications.
2. Lancez `dbo.IndexOptimize` sur la seule copie, avec ses valeurs par défaut, plus la mise à
   jour des statistiques modifiées et `@LogToTable`.
3. Lisez dans `CommandLog`, pour chaque commande, l'objet, l'index ou la statistique, le type de
   commande, et dans `ExtendedInfo` le nombre de pages et la fragmentation.
4. Mesurez de nouveau les index.

## Partie 3. Le travail de la comptabilité

1. Créez un travail de l'Agent à deux étapes T-SQL exécutées dans `DBA` : la vérification de
   la copie, puis l'entretien de ses index et de ses statistiques. L'étape 1 passe à l'étape 2
   quand elle réussit, et arrête le travail en échec sinon.
2. Planifiez-le chaque samedi à 22 h.
3. Lancez-le à la main, et lisez son historique dans `msdb.dbo.sysjobhistory`.

## Partie 4. La preuve

Écrivez la requête qui montre à la comptabilité que la demande est satisfaite : ce que le
travail a écrit dans `CommandLog`, sans erreur, la date de la dernière vérification sans erreur,
et le travail avec sa planification et son dernier résultat.

## À réfléchir

- Pourquoi `LastGoodCheckDbTime` n'a-t-il pas bougé après la vérification de la partie 1, et
  pourquoi rend-il une date antérieure à la création de la copie ?
- Où se trouve le texte des erreurs de `CHECKDB`, puisque `CommandLog` ne le garde pas ?
- Pourquoi ne peut-on pas compter les lignes de l'archive avant la réparation ?
- Combien de paiements la réparation a-t-elle coûtés ? En production, comment saurait-on
  lesquels, et que faudrait-il pour n'en perdre aucun ?
- Pour chaque index reconstruit, pourquoi une reconstruction et non une réorganisation ?
  Pourquoi `dbo.PaymentArchive` n'apparaît-il pas ? Qu'aurait fait la procédure en édition
  Standard ?
- Pourquoi des statistiques de tables de trois lignes sont-elles mises à jour ? Qu'en
  pensez-vous ?
- Lors du lancement manuel du travail, que fait l'étape 2, et pourquoi ?
- Que se passerait-il, pour l'étape 2, si la page n'avait pas été réparée ?
