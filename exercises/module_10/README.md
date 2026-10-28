# Exercice du module 10

Objectif : appliquer à une autre demande les gestes du module, un travail à plusieurs étapes
avec nouvelle tentative et étape d'échec, Database Mail et un fichier joint, un opérateur
prévenu d'un échec, et un travail de surveillance.

L'équipe du planning veut recevoir chaque lundi à 7 heures la liste des sessions de la semaine
qui commence, dans un fichier CSV. Si l'envoi échoue, l'équipe des DBA doit être prévenue. Et
chaque matin, les DBA veulent la liste des travaux de l'instance qui ont échoué la veille.

L'exercice se joue sur votre labo, avec Mailpit, le serveur SMTP de test du `compose.yaml`
(http://localhost:8025). Il n'écrit jamais dans `PachadataTraining` : `1-start.sql` en
restaure une copie, `PachadataTraining_Ex10`, que le corrigé supprime à la fin, avec ce qu'il
crée sur l'instance.

Il se fait sans le profil de l'Agent : l'avertissement des DBA passe par
`sp_notify_operator`, dans l'étape d'échec du travail.

## Les fichiers

- `1-start.sql` restaure `PachadataTraining_Ex10` (quelques secondes), y crée le schéma
  `Planning`, et affiche le nombre de sessions non annulées de la semaine du lundi 19 octobre
  2026 (44), et ce que l'instance a avant l'exercice : travaux, profils de messagerie, valeur
  de `Database Mail XPs`.
- `2-solution.sql` est le corrigé, à lire après avoir cherché. Il dure environ une minute et
  demie, la nouvelle tentative de l'étape 2 attendant une minute. Sur une instance qui ne
  joint pas Mailpit, il s'exécute de même, et ses messages finissent en `failed`.

```bash
docker exec -i sqladmcourse /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C < exercises/module_10/1-start.sql
```

## Les questions


### Partie 1. Database Mail

1. Activez Database Mail s'il ne l'est pas.
2. Créez un compte `Ex10 Mailpit` vers le serveur `mail`, port 1025, adresse d'expédition
   `planning-jobs@pachadata.example`, et un profil `Ex10 planning` qui l'utilise. Rendez le
   profil public, sans en faire le profil par défaut.
3. Envoyez un message de test à `dba-team@pachadata.example`, et suivez-le dans
   `sysmail_allitems` jusqu'à son statut final.

### Partie 2. L'opérateur et le travail

1. Créez un opérateur `Ex10 DBA team`, d'adresse `dba-team@pachadata.example`.
2. Créez une catégorie `Ex10 planning` et un travail `Ex10 weekly sessions`, propriétaire
   `sa`, de quatre étapes T-SQL :
   - étape 1, dans la copie : recrée une table vide `Planning.NextWeekSession` (identifiant,
     date de début, stage, langue, durée, formateur, salle) ; en cas d'échec, quitter en échec ;
   - étape 2 : y copie les sessions non annulées de la semaine du lundi 19 octobre 2026 ; une
     nouvelle tentative, une minute après un échec ; en cas d'échec définitif, aller à l'étape 4 ;
   - étape 3 : envoie la table à `planning@pachadata.example` en pièce jointe `sessions.csv`,
     séparée par des points-virgules, avec une ligne d'en-tête ; en cas de succès, quitter en
     réussite ; en cas d'échec, aller à l'étape 4 ;
   - étape 4 : prévient l'opérateur par `sp_notify_operator`, puis échoue elle-même.
3. Planifiez-le chaque lundi à 7 heures, et donnez-lui son serveur cible.

### Partie 3. Un succès, puis un échec

1. Lancez le travail, comptez les sessions copiées, et ouvrez le fichier dans Mailpit.
2. Faites échouer l'étape 2 par une table qui n'existe pas, relancez, et lisez l'historique de
   cette exécution.

### Partie 4. Les échecs de la veille

1. Créez un travail `Ex10 failed jobs`, planifié chaque jour à 7 h 30, qui liste les
   exécutions en échec des dernières vingt-quatre heures, avec leur heure et le nom du
   travail, et les envoie à l'opérateur quand il y en a.
2. Lancez-le, et vérifiez dans `sysmail_allitems` les messages de l'exercice, puis dans
   Mailpit.

### Partie 5. Le nettoyage

Supprimez les deux travaux et leurs planifications, la catégorie, l'opérateur, le profil et
le compte, puis la copie. Remettez `Database Mail XPs` à 0 s'il ne reste aucun profil sur
l'instance.

### À réfléchir

- Quelle valeur de `@freq_interval` donne « chaque lundi », et pourquoi ?
- Combien de lignes l'historique a-t-il pour l'exécution en échec, et que vaut `run_status`
  pour la première tentative de l'étape 2 ?
- Pourquoi l'étape 4 doit-elle échouer elle-même ?
- Pourquoi `sp_notify_operator` fonctionne-t-il ici alors que la notification d'un travail par
  `@notify_level_email` ne partirait pas sur votre labo ? Que faudrait-il pour qu'elle parte ?
- La requête jointe s'exécute dans quelle session et quelle base ? Que se passe-t-il si elle
  lit une variable de l'étape ?
- Pourquoi le fichier fait-il plus d'octets que de caractères ?
- Le travail du matin compte-t-il ses propres échecs ? Et si l'Agent est arrêté toute la nuit,
  qui prévient les DBA ?
