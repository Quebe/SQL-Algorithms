# SQL-Algorithms
Collection of algorithms written in Transact-SQL that I have developed over the years.

## Temporal - Date Segment Manipulation

The below functions are focused on transforming segmented, time sensitive information stored in a normalized database structure or for transactional processing in an aggregated method for analytics and reporting to increase ease of access, reduce complexity of joins, and provide better time series analysis. 

### Date Segment - Align Within Table

[[dbo].[DateSegments_AlignWithinTable]](https://github.com/Quebe/SQL-Algorithms/blob/master/Temporal/Date%20Segment%20Manipulation/DateSegments_AlignWithinTable.md)

Aligns multi-layered, segmented information within a table by a partition so that each segment will break with evenly. This enables easier aggregation when needing to prioritize information stored across multiple segments within a single partition.

### Date Segment - Gap Fill

[dbo].[DateSegments_FillGap]

Creates null (or fake) date segments for a temporal table/data set to ensure that there are no gaps between segments. Is used as a dependency for "DateSegments_Merge" function.

### Date Segment - Merge By Grow

[dbo].[DateSegments_MergeByGrow]

Merges and collapses multiple segments for a partition that match by aggregate fields using a grow/overlap method and returning distinct segments.

### Date Segment - Merge Tables

[dbo].[DateSegments_MergeTables]

Merges segments from 2 tables into one table given a partition.




# Reference Database for Scripts
The scripts have been developed for stand-alone execution in the dbo schema. The test examples use the AdventureWorks or WideWorldImporters sample databases from Microsoft for SQL.

AdventureWorks:
https://www.microsoft.com/en-us/download/details.aspx?id=49502


WideWorldImporters: https://github.com/Microsoft/sql-server-samples/releases/tag/wide-world-importers-v1.0

Additional data will be sourced from Kaggle data set for [Lending Club Loan Data](https://www.kaggle.com/wendykan/lending-club-loan-data) as a source of temporal data. This requires the SQLite ODBC driver if you want to directly import from a Linked Server in SQL Server.

In addition, there are some minor changes to data fields to match data types and create segments when used. 

Imported Data in as table "LoanData". Then, execute the following statements in T-SQL to prep the table. Since the data set has 1 record per member, we want to change it where a single member can have multiple loans (potentially overlapping or gapped) loans. We will simply take the member_id and divide by 10, convert back to an integer to group loans "randomly." 

<pre><code>
UPDATE LoanData SET member_id = CAST (member_id / 10 AS BIGINT);

ALTER TABLE LoanData ADD EffectiveDate DATE NULL;
GO

ALTER TABLE LoanData ADD TerminationDate DATE NULL;
GO

UPDATE LoanData SET EffectiveDate = PARSE (CAST (issue_d AS CHAR (0020)) AS date);

UPDATE LoanData SET TerminationDate = DATEADD (DAY, -1, DATEADD (MONTH, ISNULL (CAST (SUBSTRING (term, 2, 2) AS INT), 0) + 1, EffectiveDate));

DELETE FROM LoanData WHERE member_id IS NULL;

/* CHANGE DATA TYPES FROM NTEXT TO SOMETHING WORKABLE */

ALTER TABLE LoanData ALTER COLUMN [id] VARCHAR (0020);
GO

ALTER TABLE LoanData ALTER COLUMN [grade] VARCHAR (0020);
GO

ALTER TABLE LoanData ALTER COLUMN [loan_status] VARCHAR (0060);
GO

CREATE CLUSTERED INDEX LoanData_ClusterIdx ON LoanData (member_id, EffectiveDate, TerminationDate);

</code></pre>