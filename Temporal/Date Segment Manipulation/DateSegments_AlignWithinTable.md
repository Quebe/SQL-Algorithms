# PROCEDURE [dbo].[DateSegments_AlignWithinTable] (Transact-SQL)

Aligns multi-layered, segmented information within a table by a partition so that each segment will break with evenly. This enables easier aggregation when needing to prioritize information stored across multiple segments within a single partition.


## Syntax
<code>

EXEC dbo.DateSegments_AlignWithinTable 
    @tableName = 'name',
    @keyFieldList = '[comma delimited list]',
    @nonkeyFieldList = '[comma delimited list]',
    @effectiveDateFieldName = 'column name',
    @terminationDateFieldName = 'column name'

</code>

