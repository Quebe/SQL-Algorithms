# PROCEDURE [dbo].[DateSegments_MergeByGrow] (Transact-SQL)

Merges and collapses multiple segments for a partition that match by aggregate fields using a grow/overlap method and returning distinct segments. Works on a single table. 

## Syntax
<pre><code>
EXEC dbo.DateSegments_MergeByGrow

    @tableName = 'table_name',

    @fieldList = '[comma delimited list]',

    @effectiveDateFieldName = 'column_name',

    @terminationDateFieldName = 'column_name',
</code></pre>

## Arguments

__@tableName =__ 'table_name'
The name of the source table. This can be a temporary table or working table or a table in the database. Supports fully qualified table names.

__@fieldList =__ '[comma delimited list]'

A list of fields to partition (group) the segments by for alignment. This is required to contain at least 1 column name. 

__@effectiveDateFieldName =__ 'column_name'

The name of the column in the source table to use as the effective or start date of the segment. 

__@terminationDateFieldName =__ 'column_name'

The name of the column in the source table to use as the termination or end date of the segment. The termination date is assumed to be non-null (e.g. a future date like 12/31/9999). You might need to COALESCE or use ISNULL and a temporary table before passing in the data.

## Return Sets 

No return sets from stored procedure. Data is inserted directly into the Destination table.

## Remarks

This procedure takes a table (temporary or otherwise) as an input, a set of columns that represent a partition of data, and the effective and termination dates to reduce the number of segments by combining segments that are the same partition data and contigous segment dates. 

This might occur from dividing and aggregating in previous steps, and you want to reduce the number of records or aggregate across a partition that would discount fields in the logic. This allows you ignore those additional fields in reduction.

Given the segments for a given partition of information as:

<pre><code>
"A"[1]:       |-------|   
"A"[2]:               |-------|   
"B"[1]:           |-------------|
"B"[2]:                         |-------|   
</code></pre>

The above segmentation for partitions A and B become the below.

<pre><code>
"A":          |---------------|   
"B":              |---------------------|
</code></pre>

## Examples

### A. Example - Combining Loan Segments by Grade

Building on the eample in the [DateSegments_AlignWithinTable]() procedure, we can combine the individual break outs to see the overall length of time for each grade that a member has a loan in.

Below is the original data set for (319).

__Segments Aligned for Member (319) Sorted by "id"__
<pre><code>
id                   EffectiveDate TerminationDate grade                funded_amnt           loan_status
-------------------- ------------- --------------- -------------------- --------------------- ------------------------------------------------------------
474548               2010-01-01    2011-03-31      C                    18500.00              Does not meet the credit policy. Status:Charged Off
474548               2011-04-01    2013-01-31      C                    18500.00              Does not meet the credit policy. Status:Charged Off
707917               2013-09-01    2014-12-31      D                    15000.00              Charged Off
707917               2015-01-01    2015-10-31      D                    15000.00              Charged Off
707917               2015-11-01    2016-04-30      D                    15000.00              Charged Off
707917               2011-04-01    2013-01-31      D                    15000.00              Charged Off
707917               2013-02-01    2013-08-31      D                    15000.00              Charged Off
7338296              2013-09-01    2014-12-31      C                    9750.00               Fully Paid
7338296              2015-11-01    2016-04-30      C                    9750.00               Fully Paid
7338296              2015-01-01    2015-10-31      C                    9750.00               Fully Paid
7338296              2016-05-01    2016-09-30      C                    9750.00               Fully Paid
37227561             2016-05-01    2016-09-30      A                    12000.00              Current
37227561             2015-11-01    2016-04-30      A                    12000.00              Current
37227561             2016-10-01    2018-01-31      A                    12000.00              Current
37227561             2015-01-01    2015-10-31      A                    12000.00              Current
65413538             2016-05-01    2016-09-30      C                    25000.00              Current
65413538             2018-02-01    2020-11-30      C                    25000.00              Current
65413538             2015-11-01    2016-04-30      C                    25000.00              Current
65413538             2016-10-01    2018-01-31      C                    25000.00              Current

(19 row(s) affected)
</code></pre>

Our partition will be "member_id, grade". This means as we aggregate the segments together, we are ignoring the details of "id" (loan id), "funded_amnt", and "loan_status".

First, we need to create a destination table that matches the same structure as we expect back. Then, we can execute the procedure with an INSERT. 

<pre><code>
SELECT TOP 0 member_id, grade, EffectiveDate, TerminationDate INTO LoanDataGrown FROM LoanDataAligned;
GO

INSERT INTO LoanDataGrown
EXEC dbo.[DateSegments_MergeByGrow]
	@tableName = 'LoanDataAligned',
	@fieldList = 'member_id, grade',
	@effectiveDateFieldName = 'EffectiveDate',
	@terminationDateFieldName = 'TerminationDate'
;

member_id            grade                EffectiveDate TerminationDate
-------------------- -------------------- ------------- ---------------
319                  A                    2015-01-01    2018-01-31
319                  C                    2010-01-01    2013-01-31
319                  C                    2013-09-01    2020-11-30
319                  D                    2011-04-01    2016-04-30

(4 row(s) affected)
</pre><code>