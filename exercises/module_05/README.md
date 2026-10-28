# Exercice du module 5

Objectif : relire les structures de stockage d'une base reprise et les remettre en ordre. La
comptabilité de PachaData vous confie une copie de la base, `PachadataTraining_Ex05`, après
son chargement de nuit. Elle veut savoir ce que coûtent ses prospects en `nvarchar`, si ses
contraintes tiennent encore, et elle demande une table de factures partitionnée par année,
dont elle archivera ou purgera une année à la fois.

L'exercice se joue sur votre labo, dans une session. Il n'écrit jamais dans
`PachadataTraining` : il restaure une copie, que le corrigé supprime à la fin.

## Les fichiers

- `1-start.sql` restaure la copie `PachadataTraining_Ex05` et y rejoue le chargement de la
  comptabilité : deux contraintes désactivées pour le chargement, puis réactivées sans
  `WITH CHECK`. Il affiche la taille de `Contact.ProspectUS_N` et le nombre de factures par
  année de création.
- `2-solution.sql` est le corrigé, à lire après avoir cherché. Il dure moins d'une minute et
  supprime la copie. Les erreurs attendues y sont attrapées par `TRY ... CATCH`.

```bash
docker exec -i sqladmcourse /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -I < exercises/module_05/1-start.sql
```

## Partie 1. Un tas et ses enregistrements transférés

`Contact.ProspectUS_N` contient un million de prospects en `nvarchar`, rangés dans un tas.

1. Mesurez la table avec `sys.dm_db_index_physical_stats` en mode `DETAILED` : `page_count`,
   `record_count`, `forwarded_record_count`, `avg_page_space_used_in_percent`.
2. Allongez la ville des prospects dont le téléphone finit par 7 :
   `SET City = City + N' (billing address distinct from head office)' WHERE Phone LIKE N'%7'`.
   Refaites la mesure.
3. Sous `SET STATISTICS IO ON`, comptez les prospects dont le prénom commence par J, et
   relevez les lectures logiques.
4. Reconstruisez le tas, refaites la mesure et le comptage.

## Partie 2. Les contraintes, les identités, les séquences

1. Listez les clés étrangères et les contraintes de vérification que le moteur ne croit plus
   (`is_not_trusted`).
2. Sous `SET STATISTICS IO ON`, lancez deux requêtes et relevez les tables lues :
   - le nombre de factures d'avant 2010 dans la vue `dbo.InvoiceAll`, qui réunit
     `Enrollment.InvoiceHistory` (factures d'avant septembre 2010) et `Enrollment.Invoice`
     (à partir de septembre 2010) ;
   - le nombre de lignes de facture qui ont leur facture, par une jointure de
     `Enrollment.InvoiceLine` à `Enrollment.Invoice` qui ne lit que des colonnes de
     `InvoiceLine`.
3. Rendez leur confiance aux deux contraintes, vérifiez `is_not_trusted`, et relancez les
   deux requêtes.
4. Listez les clés étrangères de `Enrollment.Invoice`, `Enrollment.InvoiceLine` et
   `Enrollment.Payment` dont la colonne ne commence aucun index.
5. Créez une séquence `Enrollment.CreditNoteNumber` (`int`, à partir de 1). Prenez un numéro
   dans une transaction que vous annulez, puis prenez le numéro suivant. Supprimez la
   séquence.

## Partie 3. La compression

1. Estimez la compression `ROW`, puis `PAGE`, du tas `Contact.ProspectUS_N`, avec
   `sys.sp_estimate_data_compression_savings`.
2. Reconstruisez la table en `ROW`, mesurez ses pages dans `sys.dm_db_partition_stats`, puis
   en `PAGE`, et mesurez de nouveau.
3. Comparez avec la jumelle en `varchar`, non compressée, `Contact.ProspectUS_SQL_Latin1`.

## Partie 4. Une table de factures partitionnée

1. Créez la fonction de partition `pfInvoiceYear` sur `smalldatetime`, `RANGE RIGHT`, avec une
   borne au 1er janvier de chaque année de 2010 à 2027, et le schéma `psInvoiceYear`, toutes
   les partitions dans `PRIMARY`.
2. Créez `dbo.InvoiceByYear` (`InvoiceCode varchar(50)`, `CreationDate smalldatetime`,
   `CompanyId int NULL`, `ContactId int NULL`, `NetAmount decimal(9, 2)`) sur le schéma de
   partition et la colonne `CreationDate`, avec une clé primaire cluster sur `InvoiceCode`
   seule. Notez l'erreur, puis créez-la avec une clé primaire sur
   `(InvoiceCode, CreationDate)`. Copiez-y toutes les factures de `Enrollment.Invoice`.
3. Lisez la répartition des lignes par partition, avec la borne basse de chacune. Calculez
   par `$PARTITION.pfInvoiceYear` la partition du 31 décembre 2009, du 1er janvier 2010, du
   15 juin 2015 et du 1er janvier 2030.
4. Créez la table d'archive `dbo.InvoiceArchive`, de même structure et même clé primaire,
   dans `PRIMARY`.
5. Créez sur `dbo.InvoiceByYear` un index sur `CompanyId`, placé explicitement
   `ON [PRIMARY]`. Essayez de basculer la partition 2010 dans l'archive, puis de vider la
   partition 2011. Notez les erreurs, et recréez l'index aligné.
6. Conduisez la fenêtre glissante, chaque opération dans une transaction où vous lisez
   `database_transaction_log_record_count` dans `sys.dm_tran_database_transactions` :
   - ouvrez 2028 (`NEXT USED`, puis `SPLIT RANGE`) ;
   - archivez 2010 par `SWITCH` ;
   - purgez 2011 par `TRUNCATE TABLE ... WITH (PARTITIONS (...))` ;
   - retirez les bornes de 2010 et de 2011 par `MERGE RANGE`.
7. Pour comparer, coupez la partition 2025 au 1er juillet, puis retirez cette borne, en
   lisant aussi le journal écrit.
8. Relisez la répartition, et comptez les lignes de l'archive.

## Les questions

- Combien de prospects la mise à jour a-t-elle modifiés, et combien d'enregistrements
  transférés a-t-elle laissés ? Pourquoi pas autant ? Pourquoi `record_count` dépasse-t-il le
  million ? Combien de pages le comptage lit-il avant et après la reconstruction ?
- Quelle table la vue `dbo.InvoiceAll` cesse-t-elle de lire quand la contrainte de
  vérification redevient fiable, et pourquoi ? Quelle table la jointure cesse-t-elle de lire ?
- Pourquoi créer un index sur chaque clé étrangère n'est-il pas une règle automatique ?
- Le numéro pris dans la transaction annulée revient-il ? Que conclure pour une numérotation
  de factures sans trou ?
- D'où vient le gain de `ROW` sur `Contact.ProspectUS_N`, et pourquoi `PAGE` n'ajoute-t-il
  presque rien ? L'estimation était-elle juste ?
- Pourquoi la clé primaire doit-elle contenir `CreationDate` ? Que rend `$PARTITION` pour une
  date qui n'a aucune ligne ?
- Combien d'enregistrements de journal ont écrits l'ouverture de 2028, le `SWITCH`, le
  `TRUNCATE`, et la coupe de 2025 ? D'où vient l'écart ?
- Pourquoi garder une partition vide à chaque extrémité ?
