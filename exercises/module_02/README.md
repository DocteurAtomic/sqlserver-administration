# Exercice du module 2

Objectif : écrire le script de configuration que PachaData appliquera à chacun de ses
serveurs, l'éprouver sur cinq machines, l'appliquer au labo, puis ouvrir la connexion
administrateur dédiée et lire ses traces dans le journal d'erreurs.

Le responsable d'exploitation ne veut plus de valeurs écrites à la main serveur par serveur :
la mémoire maximale et MAXDOP doivent se calculer à partir de la mémoire et des processeurs de la machine.

L'exercice se joue sur votre labo. Il ne touche jamais `PachadataTraining` : `1-start.sql`
crée une base `ConfigLab02`, et le corrigé la supprime à la fin. Le corrigé change la
configuration de l'instance, puis lui rend ses valeurs d'origine.

## Les fichiers

- `1-start.sql` crée `ConfigLab02` et sa table `dbo.Server` : cinq serveurs de PachaData, leur
  plateforme, leur mémoire, leurs nœuds NUMA et leur charge. Pour un serveur Linux, la
  mémoire est la limite du processus SQL Server (`memory.memorylimitmb`). `PACHA-LAB` est
  votre labo.
- `2-solution.sql` est le corrigé, à lire après avoir cherché. Il dure quelques secondes.

```bash
docker exec -i sqladmcourse /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C < exercises/module_02/1-start.sql
```

## Partie 1. Le calcul sur cinq serveurs

Écrivez une requête sur `dbo.Server` qui rend, pour chaque serveur, `max_server_memory_mb`,
`maxdop_microsoft` et `maxdop`.

- La mémoire, sous Windows : la mémoire du serveur moins la réserve du système, 2 Go jusqu'à
  16 Go, 4 Go jusqu'à 64 Go, 10 % au-delà.
- La mémoire, sous Linux : 75 % de la limite du processus.
- MAXDOP selon la règle de Microsoft : un seul nœud, le nombre de processeurs logiques
  jusqu'à 8, puis 8 ; plusieurs nœuds, le nombre de processeurs logiques par nœud jusqu'à 16,
  puis la moitié, 16 au plus.
- Puis 8 au plus pour une charge `OLTP`.

## Partie 2. Le même calcul sur le labo

1. Rendez visibles les options avancées.
2. Refaites le calcul à partir des vues de l'instance : `sys.dm_os_host_info` pour la
   plateforme, `sys.dm_os_sys_info` pour la mémoire, `sys.dm_os_nodes` pour les nœuds (les
   nœuds `ONLINE` seulement).
3. Appliquez les deux valeurs, et les quatre autres réglages du module : seuil de coût du
   parallélisme à 50, `optimize for ad hoc workloads`, `backup compression default` et
   `remote admin connections` à 1.
4. Avant `RECONFIGURE`, listez les options dont `value` diffère de `value_in_use`. Après,
   recommencez.

## Partie 3. Les ports

Depuis SSMS sur votre poste, connecté à `localhost,14433` :

1. Listez les points d'écoute de l'instance.
2. Lisez le port de votre propre connexion côté serveur.

## Partie 4. La DAC

1. Dans un terminal, ouvrez la DAC :
   `docker exec -it sqladmcourse /opt/mssql-tools18/bin/sqlcmd -S admin:localhost -U sa -C`.
   Vérifiez dans cette session qu'elle passe par le point de terminaison dédié.
2. Sans la fermer, ouvrez-en une seconde depuis un autre terminal, par la même commande.
   Notez le message du client.
3. Depuis SSMS, lisez dans le journal d'erreurs les lignes de la DAC et la cause de l'échec.
   Fermez la DAC (`exit`).

## Partie 5. La DAC depuis le réseau

1. Après la partie 2, sur quelles adresses le port 1434 écoute-t-il ?
2. Ouvrez la DAC par le nom du conteneur et son port :
   `docker exec -it sqladmcourse sh -c '/opt/mssql-tools18/bin/sqlcmd -S "$(hostname),1434" -U sa -C'`.

## Si vous avez une instance Windows

Deux exercices du support présentiel ne se jouent que sous Windows ; faites-les si vous avez
une instance de test, jamais sur un serveur partagé.

- Dans le Gestionnaire de configuration, relevez le compte et le mode de démarrage de chaque
  service et comparez-les à `sys.dm_server_services`. Donnez un port fixe à une instance
  nommée, arrêtez SQL Browser et connectez-vous avec, puis sans le port.
- Retirez-vous le rôle `sysadmin`, puis retrouvez-le en mode mono-utilisateur
  (`net start MSSQLSERVER /mSQLCMD`), comme dans la vidéo 2.6.

## À réfléchir

- Pourquoi `PACHA-BI01` garde-t-il un MAXDOP de 10, et `PACHA-SQL02` 8 ?
- Quelle valeur de MAXDOP le calcul donne-t-il pour le labo, et pourquoi la vidéo en a-t-elle
  choisi une autre ?
- Sous Linux, pourquoi ne pas appliquer au labo la réserve de 2 Go de la règle Windows ?
- Quelle option sort de la requête après `RECONFIGURE`, et pourquoi ?
- Pourquoi votre connexion arrive-t-elle sur 1433 alors que vous avez visé 14433 ?
- Quel numéro d'erreur le journal donne-t-il pour la seconde DAC, et pourquoi le client ne
  le montre-t-il pas ?
- Que faudrait-il changer au labo pour ouvrir la DAC depuis SSMS sur votre poste ?
