# PROCEDURE [dbo].[DateSegments_GapFill] (Transact-SQL)

Creates null (or fake) date segments for a temporal table/data set to ensure that there are no gaps between segments. This creates a contiguous set of date segments over a partition. 

This procedure is used as a dependency for "DateSegments_MergeTables" function.


## Syntax
<pre><code>
EXEC dbo.DateSegments_GapFill

    @tableName = 'table_name',

    @keyFieldList = '[comma delimited list]',

    @nonkeyFieldList = '[comma delimited list]',

    @effectiveDateFieldName = 'column_name',

    @terminationDateFieldName = 'column_name',

    @copyNonkeyFieldValues = [0|1],

    @includeRealIndicator = [0|1]

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

__@terminationDateFieldName =__ 'column_name'

The name of the column in the source table to use as the termination or end date of the segment. The termination date is assumed to be non-null (e.g. a future date like 12/31/9999). You might need to COALESCE or use ISNULL and a temporary table before passing in the data.

__@copyNonkeyFieldValues =__ [0|1] (bit)

This determines if we copy the values from the non-key fields that we are carrying from the real segment forward into the new generated gap segment.

__@includeRealIndicator =__ [0|1] (bit)

This determines if we include an additional column on the return result set that indicates if the record was an original record or generated record. The column name is "RealRecord" and is a BIT.

## Return Sets 

Returns a table that consists of: [keyFieldList], [nonkeyFieldList], EffectiveDateFieldName, TerminationDateFieldName {, RealRecord }

Segments are created from '01/01/0001' to '12/31/9999'. You will need to reset that dates to bound the segments to a different period of time (e.g. rebounding for '01/01/1980'+).

## Remarks

This procedure takes a table (temporary or otherwise) as an input, a set of columns that represent a partition of data, and the effective and termination dates to create new segments that fill in gaps of coverage along the partition for creating contiguous segments along a partition.

The primary purpose is to create contiguous segments for supporting the DateSegments_MergeTables procedure, but it can be useful in other cases. 

Given the segments for a given partition of information as:

<pre><code>
"A":       |--------------| 
"B":                                |-------------|
</code></pre>

The stored procedure will create a new set of records ("C") that fill in the gaps of segments to ensure that for the partition the date segments of infomration is contiguous.

<pre><code>
"A":       |--------------| 
"B":                                |-------------|
"C":  <----|              |---------|             |------->
</code></pre>

This is useful when there is a high amount of turnover in the temporal data. 

## Examples

### A. Example - Filling Gaps in Employee Pay History

Not the most useful example as the AdventureWorks employee pay history tables does not have any middle gaps, but this does show a simple example of filling in the information. This example assumes you have prepped the data as recommended in the top-level readme.md.

<pre><code>

	SELECT * FROM EmployeePayHistory WHERE BusinessEntityID = 4 ORDER BY EffectiveDate;

BusinessEntityID RateChangeDate          Rate                  PayFrequency ModifiedDate            EffectiveDate TerminationDate
---------------- ----------------------- --------------------- ------------ ----------------------- ------------- ---------------
4                2010-12-05 00:00:00.000 8.62                  2            2007-11-21 00:00:00.000 2010-12-05    2013-05-30
4                2013-05-31 00:00:00.000 23.72                 2            2010-05-16 00:00:00.000 2013-05-31    2014-12-14
4                2014-12-15 00:00:00.000 29.8462               2            2011-12-01 00:00:00.000 2014-12-15    9999-12-31

(3 row(s) affected)    

-- WITHOUT RECORD FILL (LEAVE NULL)
EXEC dbo.[DateSegments_GapFill]
	@tableName = 'EmployeePayHistory', 
	@keyFieldList = 'BusinessEntityID',
	@nonkeyFieldList = 'Rate, PayFrequency',
	@effectiveDateFieldName = 'EffectiveDate',
	@terminationDateFieldName = 'TerminationDate',
	@copyNonkeyFieldValues = 0, -- COPY THE VALUES FROM A REAL RECORD OR SET TO NULL
	@includeRealIndicator = 1 -- INCLUDE AN INDICATOR IN THE RESULT SET FOR REAL/FAKE RECORD 
;

BusinessEntityID Rate                  PayFrequency EffectiveDate TerminationDate RealRecord
---------------- --------------------- ------------ ------------- --------------- ----------
4                NULL                  NULL         0001-01-01    2010-12-04      0
4                8.62                  2            2010-12-05    2013-05-30      1
4                23.72                 2            2013-05-31    2014-12-14      1
4                29.8462               2            2014-12-15    9999-12-31      1

</code></pre>

