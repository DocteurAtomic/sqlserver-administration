# Exercice du module 7

Objectif : donner à la plateforme d'e-learning de PachaData un compte qui ne fait que ce
qu'elle fait, puis réparer son utilisateur sur un serveur de test. La base de l'exercice,
`PachadataElearning_Ex07`, tient lieu de la base de la plateforme. La plateforme lit les
modules et la progression, lit les stagiaires sans leur date de naissance, et enregistre une
progression par une procédure prévue pour cela.

L'exercice se joue sur votre labo, dans une seule session. Il n'écrit jamais dans
`PachadataTraining` : il crée une base à part, que le corrigé supprime à la fin, avec tout ce
qu'il a créé sur l'instance (une connexion, une copie de test de la base, un fichier de
sauvegarde et son historique).

## Les fichiers

- `1-start.sql` crée la base `PachadataElearning_Ex07` en lisant `PachadataTraining` :
  `Elearning.Module` (992 lignes), `Elearning.Progress` (251 965 lignes), `Contact.Trainee`
  (37 656 stagiaires, avec leur date de naissance) et la procédure `Elearning.RecordProgress`.
  Il crée aussi le répertoire de la sauvegarde, `/var/opt/mssql/backup/exercise_07`.
- `2-solution.sql` est le corrigé, à lire après avoir cherché. Il dure quelques secondes
  et nettoie ce qu'il crée. Le répertoire vide reste : le T-SQL ne le supprime pas.

```bash
docker exec -i sqladmcourse /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C < exercises/module_07/1-start.sql
docker exec sqladmcourse rm -rf /var/opt/mssql/backup/exercise_07   # à la toute fin
```

Pour essayer la connexion de la plateforme par une vraie connexion, passez son mot de passe
par l'environnement, jamais par `-P` :

```bash
docker exec -it -e SQLCMDPASSWORD='<le mot de passe choisi>' sqladmcourse \
    /opt/mssql-tools18/bin/sqlcmd -S localhost -U PachadataElearning -C
```


## Partie 1. La connexion et l'utilisateur

1. Créez la connexion SQL `PachadataElearning` avec un mot de passe d'une seule famille de
   caractères. Que répond le labo ?
2. Créez-la avec un mot de passe conforme, la politique vérifiée, sans expiration, et
   `PachadataElearning_Ex07` comme base par défaut. Quel algorithme de hachage lisez-vous ?
3. Avant de créer l'utilisateur, essayez d'entrer dans la base sous cette connexion
   (`EXECUTE AS LOGIN`, ou une vraie connexion par `sqlcmd`). Quelle erreur, et quel état de
   l'erreur 18456 dans le journal ?
4. Créez l'utilisateur `ElearningPlatform` et vérifiez son lien avec la connexion.

## Partie 2. Le rôle et les permissions

1. Créez le rôle `ElearningApp`, appartenant à `dbo`, et mettez-y l'utilisateur.
2. Donnez au rôle la lecture du schéma `Elearning`, la lecture de `Contact.Trainee` sans la
   colonne `BirthDate`, et l'exécution de `Elearning.RecordProgress`. Rien d'autre.
3. Sous l'identité de l'utilisateur, vérifiez ces droits par `HAS_PERMS_BY_NAME` et
   `sys.fn_my_permissions`. Que rend un `SELECT *` sur `Contact.Trainee` ?
4. Toujours sous son identité, mettez à jour une progression par un `UPDATE` direct, puis par
   la procédure. Lequel passe, et pourquoi ?
5. Écrivez la requête qui prouve que la connexion n'a rien au niveau de l'instance et que son
   utilisateur n'est membre que de son rôle.

## Partie 3. L'orphelin du serveur de test

1. Sauvegardez la base en copie seule. Générez, sur ce « serveur source », la commande qui
   recrée la connexion avec son SID et le hachage de son mot de passe, et gardez-la.
2. Jouez le serveur de test : supprimez la connexion, recréez-la à la main avec le même nom et
   le même mot de passe, puis restaurez la sauvegarde sous le nom
   `PachadataElearning_Ex07_Test`.
3. Cherchez les utilisateurs orphelins dans les deux bases. Pourquoi la base d'origine en
   a-t-elle un aussi ?
4. Réparez sans `ALTER USER`, avec la commande gardée à la question 1. Vérifiez que la copie de
   test s'ouvre sous la connexion et que l'utilisateur a gardé son rôle.

## Partie 4. Le nettoyage

Supprimez les deux bases, la connexion, le fichier de sauvegarde et son historique dans
`msdb`.

## Les questions

- Pourquoi la connexion créée à la main, avec le même nom et le même mot de passe, ne suffit-elle
  pas ?
- Que gagne la réparation par la commande générée sur la réparation par `ALTER USER`, quand il
  y a plusieurs bases et plusieurs serveurs ?
- La procédure met à jour `Elearning.Progress` alors que l'utilisateur n'a pas `UPDATE` sur la
  table. Qu'est-ce qui casserait ce comportement ?
- Une base partiellement autonome aurait-elle évité la partie 3 ? À quel prix ?
