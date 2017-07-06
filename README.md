# SQL-Algorithms
Collection of algorithms written in Transact-SQL that I have developed over the years.


__Reference Database for Scripts:__
The scripts have been developed for stand-alone execution in the dbo schema. The test examples use the AdventureWorks or WideWorldImporters sample databases from Microsoft for SQL.

AdventureWorks:
https://www.microsoft.com/en-us/download/details.aspx?id=49502


WideWorldImporters: https://github.com/Microsoft/sql-server-samples/releases/tag/wide-world-importers-v1.0


## Temporal - Date Segment Manipulation

### Date Segment - Gap Fill

[dbo].[DateSegments_FillGap]

Creates null (or fake) date segments for a temporal table/data set to ensure that there are no gaps between segments. Is used as a dependency for "DateSegments_Merge" function.

