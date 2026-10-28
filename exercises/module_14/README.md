# Exercice du module 14

Objectif : surveiller l'outil de planning de PachaData. L'équipe du planning déploie une
nouvelle version ce soir, et elle se plaint que l'écran des sessions se fige de temps en
temps. Vous lisez dans les journaux ce que le déploiement a fait, vous trouvez la tête d'une
chaîne de blocage et vous historisez l'activité, vous tuez une transaction volumineuse en
suivant son annulation, puis vous tracez les changements de structure du développeur du
planning.

L'exercice se joue sur votre labo. Il n'écrit jamais dans `PachadataTraining` : `1-start.sql`
en restaure une copie, `PachadataTraining_Ex14`, sur laquelle il désactive RCSI
(`READ_COMMITTED_SNAPSHOT`) : sur cette copie, une lecture attend une écriture, comme sur une
base qui n'a jamais activé RCSI. Les parties 2 et 3 demandent `sp_WhoIsActive` dans `DBA` :
lancez d'abord `demos/module_14/02a-install-whoisactive.sh` si vous ne l'avez pas fait.

## Les fichiers

- `1-start.sql` restaure la copie (quelques secondes), y crée l'utilisateur sans connexion
  `PlanningDev`, membre de `db_ddladmin`, et écrit un message dans le journal d'erreurs.
- `3-window-a.sql`, `3-window-b.sql`, `3-window-c.sql` : les trois fenêtres de la partie 2.
- `4-big-transaction.sql` : la transaction de la partie 3.
- `2-solution.sql` (parties 1 et 4, une session) et `5-solution-blocking.sql` (parties 2 et 3,
  bloc par bloc) sont le corrigé, à lire après avoir cherché.
- `6-cleanup.sql` supprime la copie, le travail de l'Agent et la table d'historique.

```bash
docker exec -i sqladmcourse /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C < exercises/module_14/1-start.sql
docker exec -i sqladmcourse /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C < exercises/module_14/6-cleanup.sql   # à la fin
```

## Partie 1. Les journaux

1. Retrouvez dans le journal d'erreurs courant ce que `1-start.sql` a fait à la copie : la
   restauration, puis les options de base modifiées. Une recherche sur deux mots suffit.
2. Retrouvez le message du déploiement, en limitant la recherche à la dernière heure, le plus
   récent d'abord.
3. Dans le journal de l'Agent, listez les erreurs et les avertissements (`ErrorLevel` 1 et 2).
   Que disent-ils de votre labo ?
4. Listez les fichiers du journal d'erreurs, et lisez l'heure du dernier démarrage de
   l'instance. Pourquoi cette heure compte-t-elle quand on lit une vue de gestion dynamique ?

## Partie 2. La chaîne de blocage et l'historique

1. Lancez dans trois fenêtres, à quelques secondes d'intervalle, `3-window-a.sql` (le
   planificateur change la salle de la session 17791 et laisse sa transaction ouverte),
   `3-window-b.sql` (le portail des formateurs lit la session) et `3-window-c.sql` (le
   formateur ajoute une remarque).
2. Dans une quatrième fenêtre, interrogez `sys.dm_exec_requests` sur la copie, en ne gardant
   que les sessions des utilisateurs. Qui attend, quoi, derrière qui ?
3. Écrivez une requête qui donne la tête de chaîne et le nombre de sessions bloquées
   derrière elle, en remontant `blocking_session_id` (une expression de table commune
   récursive convient).
4. Obtenez le même résultat avec `DBA.dbo.sp_WhoIsActive`, filtrée sur la base de la copie,
   la tête en premier.
5. Historisez l'activité : créez `DBA.dbo.ActivityHistory` à partir de ce que
   `sp_WhoIsActive` dit de sa propre sortie (`@return_schema`), ajoutez un index cluster sur
   `collection_time`, puis un travail de l'Agent, `Exercise 14 - Activity history`, qui
   collecte chaque minute et purge les relevés de plus de sept jours. Lancez-le, puis comptez
   les relevés deux minutes plus tard, et lisez la taille de la table.
6. Terminez : `ROLLBACK;` dans la fenêtre A. Que rendent alors les fenêtres B et C ?

## Partie 3. Tuer une transaction volumineuse

1. Lancez `4-big-transaction.sql` : le recalcul mensuel de la progression e-learning, en une
   transaction qui modifie les 251 965 lignes de `Elearning.Progress`, puis attend dix
   minutes.
2. Avant de la tuer, regardez-la : sa connexion, son programme, son début, le journal qu'elle
   a écrit (`sys.dm_tran_database_transactions`), et ses verrous.
3. Tuez-la, et suivez l'annulation par `KILL ... WITH STATUSONLY` et par `percent_complete`,
   toutes les demi-secondes, jusqu'à l'erreur qui dit que c'est fini. Que reçoit la fenêtre
   tuée ?

## Partie 4. Les changements de structure du planning

1. Créez dans la copie une table `dbo.DdlLog` et un déclencheur de base `PlanningDdl`, pour
   `DDL_DATABASE_LEVEL_EVENTS`, qui y écrit le type d'événement, l'utilisateur, l'objet et la
   commande lus dans `EVENTDATA()`. Écrivez-le d'abord sans précaution.
2. Sous l'identité de `PlanningDev` (`EXECUTE AS USER`), créez une table
   `Course.RoomRequest`. Que se passe-t-il, et la table existe-t-elle ?
3. Entourez l'insertion d'un `TRY ... CATCH` vide, et recommencez. Puis ajoutez
   `SET XACT_ABORT OFF`, recommencez, et lisez le journal. Puis ajoutez
   `WITH EXECUTE AS N'dbo'`, recommencez, et relisez-le.
4. Comptez les événements que couvre le déclencheur, dans `sys.trigger_events`.

## À réfléchir

- Pourquoi la fenêtre C désigne-t-elle la fenêtre B, et pas la fenêtre A ? Que vaut
  `open_tran_count` pour chacune ?
- Sur `PachadataTraining`, avec RCSI, la fenêtre B aurait-elle attendu ?
- Pourquoi les paramètres de la collecte doivent-ils être exactement ceux de
  `@return_schema` ? Que contient une ligne d'historique, et pourquoi faut-il protéger cette
  table comme les données elles-mêmes ?
- Que valait la première estimation de `WITH STATUSONLY` ? Combien de lignes `OBJECT` la
  transaction volumineuse tient-elle dans `sys.dm_tran_locks`, et pourquoi ce nombre ?
- Pourquoi le `TRY ... CATCH` seul ne sauve-t-il rien ? Qu'est-ce qui ne va pas dans la
  version avec `SET XACT_ABORT OFF` sans `EXECUTE AS`, qui ne renvoie pourtant plus d'erreur ?
- Quel utilisateur la dernière version inscrit-elle, et pourquoi pas `dbo` ?

Les exercices du support présentiel sur les événements étendus et le Query Store (E52), sur
le rapport des processus bloqués et les interblocages (E54) et sur le gouverneur de
ressources (E55) ont leur place dans le cours `sqlserver-optimisation` : modules 4 et 5, V7,
D5.
