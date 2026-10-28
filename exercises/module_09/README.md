# Exercice du module 9

Objectif : donner au portail des formateurs une sécurité au niveau des lignes adaptée à une
application qui se connecte avec un seul compte, puis auditer les modifications du portail et
les changements de la politique par les administrateurs.

Le portail des formateurs est une application web. Elle se connecte avec un seul compte,
`TrainerPortal`, pour tous les formateurs. Chaque formateur ne doit voir que ses propres
tarifs (`Trainer.TrainerRate`) et ses propres sessions (`Course.Session`), et ne met à
jour que ses sessions, pour y ajouter une remarque. L'équipe du planning, rôle `Planning`, voit tout.

L'exercice se joue sur votre labo, dans une session neuve. Il n'écrit jamais dans
`PachadataTraining` : `1-start.sql` en restaure une copie, `PachadataTraining_Ex09`, que le
corrigé supprime à la fin, avec l'audit qu'il crée sur l'instance.

## Les fichiers

- `1-start.sql` restaure `PachadataTraining_Ex09` (quelques secondes) et y crée les
  utilisateurs sans connexion `TrainerPortal` (lecture des tarifs, lecture et mise à jour des
  sessions) et `Camille`, membre du rôle `Planning` (lecture des deux tables). Il affiche le
  nombre de tarifs et de sessions des formateurs 1 et 2.
- `2-solution.sql` est le corrigé, à lire après avoir cherché. Il dure quelques secondes et
  nettoie ce qu'il crée, sauf le fichier d'audit, que le T-SQL ne sait pas supprimer :

```bash
docker exec -i sqladmcourse /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C < exercises/module_09/1-start.sql
docker exec sqladmcourse sh -c 'rm /var/opt/mssql/data/Ex09Audit_*.sqlaudit'   # à la toute fin
```

## Partie 1. Un seul compte, des formateurs différents

1. Créez un schéma `Security` et une fonction de prédicat `Security.fn_TrainerAccess`, liée
   au schéma, qui laisse passer une ligne quand l'utilisateur est `TrainerPortal` et que le
   formateur de la ligne est celui que le portail a déposé dans le contexte de session, sous
   la clé `TrainerId`. Elle laisse aussi passer `Planning` et `db_owner`.
2. Posez-la dans une politique de sécurité : en filtre sur `Trainer.TrainerRate` et sur
   `Course.Session`, et en blocage `AFTER UPDATE` sur `Course.Session`.
3. Comptez les tarifs et les sessions visibles par `Camille`, par vous-même, puis par
   `TrainerPortal` sans contexte.
4. Toujours sous l'identité de `TrainerPortal`, déposez le formateur 1 dans le contexte par
   `sp_set_session_context`, en lecture seule, et recomptez. Essayez ensuite de passer au
   formateur 2.
5. Pour le formateur 1, ajoutez une remarque à sa session 17791, puis à la session 17726, qui
   appartient au formateur 2. Enfin, essayez de donner la session 17791 au formateur 2.

## Partie 2. L'audit du portail et de la politique

1. Créez un audit de serveur `Ex09Audit` vers `/var/opt/mssql/data/` (10 Mo par fichier, deux
   fichiers au plus, `QUEUE_DELAY` de 1000, `ON_FAILURE = CONTINUE`), et une spécification de
   serveur qui enregistre les changements d'audit (`AUDIT_CHANGE_GROUP`).
2. Dans `PachadataTraining_Ex09`, créez une spécification de base qui enregistre les `UPDATE`
   sur `Course.Session` par tout le monde, et toute modification d'un objet de schéma. Activez
   les spécifications, puis l'audit, et vérifiez son état.
3. Provoquez des événements : une remarque ajoutée par le portail à la session 17816 du
   formateur 1, puis, sous votre identité, la politique désactivée et réactivée.
4. Lisez l'audit par `sys.fn_get_audit_file`, avec le nom de chaque action tiré de
   `sys.dm_audit_actions`.

## Partie 3. Le nettoyage

Désactivez et supprimez les spécifications et l'audit, dans le bon ordre, puis la base
`PachadataTraining_Ex09`. Vérifiez qu'il ne reste rien sur l'instance, et supprimez le
fichier d'audit.

## À réfléchir

- Que voit `TrainerPortal` sans contexte, et pourquoi est-ce le bon comportement ?
- Pourquoi `@read_only = 1` est-il indispensable ? Que faut-il faire pour recommencer l'essai
  avec un autre formateur ?
- La remarque ajoutée à la session 17726 ne rend pas d'erreur. Combien de lignes modifie-t-elle,
  et pourquoi ?
- Que se passerait-il, sans le prédicat de blocage, quand le portail donne une session à un
  autre formateur ?
- Le contournement d'un problème connu de SQL Server 2025 touche `SESSION_CONTEXT`. Lequel, et
  qu'en faites-vous pour les rapports du planning ?
- Qui est enregistré comme auteur de la mise à jour du portail, dans quelles colonnes ?
- En quoi l'audit de `ALTER SECURITY POLICY` répond-il à la limite de la sécurité au niveau
  des lignes face à `db_owner` ?
- Que reste-t-il après la suppression de l'audit, et où faudrait-il envoyer ces fichiers en
  production ?
