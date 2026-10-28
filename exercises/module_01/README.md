# Exercice du module 1

Objectif : établir la fiche d'une instance qu'on reprend, pour le registre des serveurs de
PachaData. Le responsable de l'exploitation veut savoir depuis quand elle tourne, quels
services elle a, quelles bases sont restées sous son niveau de compatibilité, sur quelle
branche de maintenance elle se trouve et à quelle famille d'édition elle appartient.

L'exercice se joue sur votre labo, dans une session. Il n'écrit jamais dans
`PachadataTraining` : il crée deux petites bases, que le corrigé supprime à la fin.

## Les fichiers

- `1-start.sql` crée les deux bases de l'exercice, ce qu'un administrateur trouve sur une
  instance reprise d'une autre équipe : `Exercise01_Legacy`, migrée depuis SQL Server 2016 et
  laissée au niveau 130, avec une table de codes de stages ; `Exercise01_New`, créée la veille
  par un développeur, avec les options de `model`.
- `2-solution.sql` est le corrigé, à lire après avoir cherché. Il dure quelques secondes et
  supprime les deux bases. L'erreur attendue de la partie 3 y est attrapée par
  `TRY ... CATCH`.

```bash
docker exec -i sqladmcourse /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -I < exercises/module_01/1-start.sql
```

## Partie 1. Le démarrage

1. Lisez l'heure de démarrage de l'instance dans `sys.dm_os_sys_info`, et calculez depuis
   combien de minutes elle tourne.
2. Retrouvez la même heure par deux autres chemins : la date de création de `tempdb` dans
   `sys.databases`, et `last_startup_time` dans `sys.dm_server_services`.

## Partie 2. Les services

1. Listez les services de l'instance, leur type de démarrage, leur état et leur compte.
2. Comparez avec ce qu'afficherait une instance sous Windows.

## Partie 3. Les niveaux de compatibilité

1. Calculez le niveau de compatibilité de l'instance à partir de
   `SERVERPROPERTY('ProductMajorVersion')`, et listez les bases qui sont en dessous.
2. Lisez le mode de récupération de `Exercise01_New` et celui de `model`.
3. Dans `Exercise01_Legacy`, cherchez avec `REGEXP_LIKE` les codes de stages de la forme
   `SQL-ADM-01`, c'est-à-dire le motif `^[A-Z]{2,3}-[A-Z]{3}-[0-9]{2}$`. Que répond le
   moteur ?
4. Montez la base au niveau de l'instance, et relancez la requête.

## Partie 4. La branche et l'édition

1. Écrivez la requête qui dit, à partir de `SERVERPROPERTY('ProductVersion')`, si une instance
   SQL Server 2025 est sur la branche CU ou sur la branche GDR.
2. Traduisez `SERVERPROPERTY('EngineEdition')` en famille d'édition.
3. Ouvrez la page des builds de SQL Server 2025
   (<https://learn.microsoft.com/fr-fr/troubleshoot/sql/releases/sqlserver-2025/build-versions>)
   et retrouvez-y votre build. Combien de CU de retard votre instance a-t-elle ?

## Partie 5. La ligne du registre

Écrivez une requête qui rend, en une ligne, ce que le registre des serveurs doit garder :
nom, build, niveau de mise à jour, `EngineEdition`, heure de démarrage, nombre de bases
utilisateur, nombre de bases sous le niveau de l'instance. Relancez-la après la partie 3.

## Les questions

- Pourquoi la date de création de `tempdb` donne-t-elle l'heure du dernier démarrage ?
- Sous Linux, `sys.dm_server_services` ne rend que deux lignes. Quels services une instance
  Windows y montrerait-elle en plus ? Où lit-on l'état de SQL Server Browser, qui n'y figure
  jamais, et à quelles instances sert-il ?
- Le moteur de 2025 contient `REGEXP_LIKE`. Pourquoi ne le trouve-t-il pas au niveau 130, et
  pourquoi est-ce voulu ?
- Que coûte, à terme, une base créée sans y penser en mode `FULL` ?
- Pourquoi un script teste-t-il `EngineEdition` plutôt que le libellé de `Edition` ?
- Le seuil de 4000 vaut pour SQL Server 2025. Où trouvez-vous celui de SQL Server 2022 ?
