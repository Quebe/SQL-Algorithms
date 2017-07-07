# PROCEDURE [dbo].[DateSegments_MergeTables] (Transact-SQL)

Merges and collapses multiple segments for a partition that match by aggregate fields using a grow/overlap method and returning distinct segments.

Dependecy: "DateSegments_GapFill" procedure.

__Warning:__ This will drop records that do not have at least 1 matching partition between the 2 tables. In otherwords, it acts like a full join between the table for determining record selection for the partition but not for the segmentation.


## Syntax
<pre><code>
EXEC dbo.DateSegments_GapFill

    @table1Name = 'table_name',

    @table1KeyFieldList = '[comma delimited list]',

    @table1NonkeyFieldList = '[comma delimited list]',

    @table1EffectiveDateFieldName = 'column_name',

    @table1TerminationDateFieldName = 'column_name',

    @table1CopyNonkeyFieldValues = [0|1],


    @table2Name = 'table_name',

    @table2KeyFieldList = '[comma delimited list]',

    @table2NonkeyFieldList = '[comma delimited list]',

    @table2EffectiveDateFieldName = 'column_name',

    @table2TerminationDateFieldName = 'column_name',

    @table2CopyNonkeyFieldValues = [0|1],


    @destinationTableName = 'table_name'
    
</code></pre>

## Arguments

__@table1Name =__ 'table_name'
The name of the source table. This can be a temporary table or working table or a table in the database. Supports fully qualified table names.

__@table1KeyFieldList =__ '[comma delimited list]'

A list of fields to partition (group) the segments by for alignment. This is required to contain at least 1 column name. 

__@table1NonkeyFieldList =__ '[comma delimited list']

A list of fields to carry with the division of segments for output. If left empty, only the key fields and date fields will be returned. 

__@table1EffectiveDateFieldName =__ 'column_name'

The name of the column in the source table to use as the effective or start date of the segment. 

__@table1TerminationDateFieldName =__ 'column_name'

The name of the column in the source table to use as the termination or end date of the segment. The termination date is assumed to be non-null (e.g. a future date like 12/31/9999). You might need to COALESCE or use ISNULL and a temporary table before passing in the data.

__@table1CopyNonkeyFieldValues =__ [0|1] (bit)

This determines if we copy the values from the non-key fields that we are carrying from the real segment forward into the new generated gap segment.

__@table2Name =__ 'table_name'
The name of the source table. This can be a temporary table or working table or a table in the database. Supports fully qualified table names.

__@table2KeyFieldList =__ '[comma delimited list]'

A list of fields to partition (group) the segments by for alignment. This is required to contain at least 1 column name. 

__@table2NonkeyFieldList =__ '[comma delimited list']

A list of fields to carry with the division of segments for output. If left empty, only the key fields and date fields will be returned. 

__@table2EffectiveDateFieldName =__ 'column_name'

The name of the column in the source table to use as the effective or start date of the segment. 

__@table2TerminationDateFieldName =__ 'column_name'

The name of the column in the source table to use as the termination or end date of the segment. The termination date is assumed to be non-null (e.g. a future date like 12/31/9999). You might need to COALESCE or use ISNULL and a temporary table before passing in the data.

__@table2CopyNonkeyFieldValues =__ [0|1] (bit)

This determines if we copy the values from the non-key fields that we are carrying from the real segment forward into the new generated gap segment.


## Return Sets 


## Remarks


## Examples

### A. Example 
