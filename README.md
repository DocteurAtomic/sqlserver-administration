# SQL Server, l'administration

Labo, démonstrations et exercices du cours en ligne
[« SQL Server, l'administration »](https://www.docteuratomic.com) de Docteur Atomic.

## Le labo

Il faut Docker (ou Podman) avec `compose`, `curl` et un shell bash (sous Windows, WSL ou
Git Bash), et environ 6 Go de mémoire libre.

    git clone https://github.com/DocteurAtomic/sqlserver-administration.git
    cd sqlserver-administration
    ./setup/install.sh

Le script télécharge la sauvegarde de `PachadataTraining` (626 Mo), vérifie sa somme
SHA-256, démarre SQL Server 2025 Developer dans le conteneur `sqladmcourse` et restaure la
base. Avec Podman : `COMPOSE="podman compose" ENGINE=podman ./setup/install.sh`.

Le conteneur est limité à 4 Go de mémoire et 2 processeurs. L'Agent SQL Server est actif.

Se connecter : SSMS ou un autre client sur `localhost,14433`, utilisateur `sa`, mot de passe
`Course-2026!lab` (un mot de passe de labo, à ne jamais reprendre ailleurs ;
`MSSQL_SA_PASSWORD` et `SQLPORT` le changent avant le premier démarrage).

## Le contenu

- `demos/module_XX` : les scripts joués dans les vidéos du module, dans l'ordre de leur
  numéro. `00-setup.sql` restaure `PachadataTraining` par `master.dbo.reset_training` et la
  met dans l'état que le module attend. `99-cleanup.sql`, quand il existe, rend l'instance à
  son état d'origine. L'en-tête de chaque script dit où il se joue.
- `exercises/module_XX` : les fichiers de l'exercice du module, corrigé compris.
- `setup/run-scripts.sh` rejoue tous les scripts qui tournent seuls ; l'intégration continue
  le lance à chaque modification.

Jouez ces scripts sur le labo, jamais sur un serveur de production : ils changent la
configuration de l'instance, créent des connexions, chiffrent et restaurent des bases.

## La base

`PachadataTraining` est la base de démonstration anglaise de Pachadata : un organisme de
formation fictif, ses stages, sessions, inscriptions, factures et sa plateforme
d'e-learning. Les personnes sont fictives. Sa documentation est dans le dépôt
[rudi-bruchez/formations](https://github.com/rudi-bruchez/formations/tree/main/bases-exemples/PachadataTraining).
La sauvegarde n'est pas dans ce dépôt, le script la télécharge.

## Licence

Le code est sous licence MIT ([`LICENSE`](LICENSE)).

---

# SQL Server Administration

Lab, demos and exercises of the Docteur Atomic online course on SQL Server administration.
Run `./setup/install.sh` (Docker or Podman with compose, curl, bash, about 6 GB of free
memory): it downloads the `PachadataTraining` backup, checks its SHA-256, starts SQL Server
2025 Developer (4 GB, 2 processors, Agent on) and restores the database. `demos/` holds the
scripts shown in the videos and `exercises/` the exercise files, one folder per module; each
module's `00-setup.sql` restores the database to the state the module expects. The code is
released under the MIT license.
