# PROCEDURE [dbo].[DateSegments_AlignWithinTable] (Transact-SQL)

Aligns multi-layered, segmented information within a table by a partition so that each segment will break with evenly. This enables easier aggregation when needing to prioritize information stored across multiple segments within a single partition.


## Syntax
<pre><code>
EXEC dbo.DateSegments_AlignWithinTable 

    @tableName = 'table_name',

    @keyFieldList = '[comma delimited list]',

    @nonkeyFieldList = '[comma delimited list]',

    @effectiveDateFieldName = 'column_name',

    @terminationDateFieldName = 'column_name'

</code></pre>

## Arguments

__@tableName =__ 'table_name'
The name of the source table. This can be a temporary table or working table or a table in the database. Supports fully qualified table names.

__@keyFieldList =__ '[comma delimited list]'

A list of fields to partition (group) the segments by for alignment. This is required to contain at least 1 column name. 

__@nonkeyFieldList =__ '[comma delimited list']

A list of fields to carry with the division of segments for output. If left empty, only the key fields and date fields will be returned. 

__@effectiveDateFieldName =__ 'column_name'

The name of the column in the source table to use as the effective or start date of the segment. 

__@terminationDateFieldName =__ 'column_name

The name of the column in the source table to use as the termination or end date of the segment.