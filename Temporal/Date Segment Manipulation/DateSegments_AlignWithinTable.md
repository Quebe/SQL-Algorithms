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

The name of the column in the source table to use as the termination or end date of the segment. The termination date is assumed to be non-null (e.g. a future date like 12/31/9999). You might need to COALESCE or use ISNULL and a temporary table before passing in the data.

## Return Sets 

Returns a table that consists of: [keyFieldList], [nonkeyFieldList], EffectiveDateFieldName, TerminationDateFieldName

## Remarks

This procedure takes a table (temporary or otherwise) as an input, a set of columns that represent a partition of data, and the effective and termination dates to align the breaks in segments given multi-layer segmented information.

As an example, let's assume that we are working with people that can subscribe to a membership based on a set of eligibility conditions or reasons that provides benefits. We want to track those reasons of eligibility independently as they are temporal and transactional processing will be "as of date" type of processing, but in time series analysis or analytics, we might be looking at the "most important" reason at any time and how that changes or responds to external factors. 

Our tables might look like: Person -> Eligibility, in which a Person can have one or more records with an "EligibilityType" categorization and an effective and termination date for that segment. It might include other time sensitive information related to that eligibility (e.g. TerminationReason). 

Because the person might have multiple segments (conditions, eligibility, behaviors, etc.), the table relationship is one-to-many with no constraints on between reasons other than there can be no overlap of segments given the same qualifier for a partition (e.g. a Person could not have overlapping segments that are both set to Reason "A").

The segments might look like the below for a single person. The source table represents a transactional view of the data in which it is easier to pull an aggregate "as of date" but harder to see the length of the "most important".

<pre><code>
"A"[1]:         |----------------------|
"A"[2]:                                |-------------|
"B":       |--------------| 
"C":                  |-----------------------|
</code></pre>

The stored procedure will break the segments as the align for that specific person. 

<pre><code>
"A"[1]:         |-----|-----------------|
"A"[2]:                                 |-----|--------|
"B":       |----|-----|---| 
"C":                  |---|-------------|-----|
</code></pre>

The resultant set of segments can be quickly flatten based on a set of business rules that prioritizes the segment into an order list. If the priority was to select "B", "C", and then "A", the flatten version might look like: 

<pre><code>
"A":                                          |--------|
"B":       |----|-----|---| 
"C":                      |-------------|-----|
</code></pre>

In addition, since the segments line up, you could aggregate a column or set of values across a time period know that the all segments would share the same effective and termination date for that set of overlapping segments. 

The number of segments can be reduced using the "DateSegment_MergeByGrow" stored procedure to produce the following result:

<pre><code>
"A":                                          |--------|
"B":       |--------------| 
"C":                      |-------------------|
</code></pre>


## Examples

### A. Example - Flattening Loan Data

The below example uses the loan data from Kaggle data set from [Lending Club Loan Data](https://www.kaggle.com/wendykan/lending-club-loan-data). You will need to import the table into SQL Server using the [ODBC SQLite database driver](http://www.ch-werner.de/sqliteodbc/).

See the top-level [readme.md](https://github.com/Quebe/SQL-Algorithms/blob/master/README.md) on how to prep the table for analysis. 

<pre><code>
CREATE TABLE LoanDataAligned (member_id BIGINT, id VARCHAR (0020), grade VARCHAR (0020), funded_amnt MONEY, loan_status VARCHAR (0060), EffectiveDate DATE, TerminationDate DATE);

INSERT INTO LoanDataAligned
EXEC dbo.DateSegments_AlignWithinTable
	@tableName = 'LoanData', 
	@keyFieldList = 'member_id',
	@nonkeyFieldList = 'id, grade, funded_amnt, loan_status', 
	@effectiveDateFieldName = 'EffectiveDate',
	@terminationDateFieldName = 'TerminationDate'
;
</code></pre>

What this does is for each member (the partition by @keyFieldList), we will break apart the loan segments (each member can have one or loans during a time period) to allow use to easily aggregate later. 

__Original Set of Segments for Member (319) Sorted by "id"__
<pre><code>
id                   EffectiveDate TerminationDate grade                funded_amnt            loan_status
-------------------- ------------- --------------- -------------------- ---------------------- ------------------------------------------------------------
474548               2010-01-01    2013-01-31      C                    18500                  Does not meet the credit policy. Status:Charged Off
707917               2011-04-01    2016-04-30      D                    15000                  Charged Off
7338296              2013-09-01    2016-09-30      C                    9750                   Fully Paid
37227561             2015-01-01    2018-01-31      A                    12000                  Current
65413538             2015-11-01    2020-11-30      C                    25000                  Current

(5 row(s) affected)
</code></pre>

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

Now, we can aggregate across the segments as they line up and feel confident in the results. This allows us to see the trends over time of multiple loans in aggregation. This is one example of what you could do. You could use the "grade" or another attribute to pick out the "most important" information for that time period and use that as the primary segment - not just aggregate by window the result by ranking. 

__Warning:__ Each row no longer represents a specific loan. Meaning the individual start/stop, term, of that loan is lost because we didn't carry those fields forward (e.g. "issue_d" and "term"). We could simply carry forward an overarching set of loan dates in the non-key field list. The Effective and Termination dates returned are the time period for each the information is valid for on that row. The purpose is to look at aggregation and trends over time series and not specifically at 1 individual instance.

<pre><code>
SELECT 
        EffectiveDate, TerminationDate,
        SUM (funded_amnt) AS TotalFundedAmount, 
        MAX (funded_amnt) AS LargestFundedAmount,
        MIN (grade) AS GradeLowest,
        COUNT (DISTINCT (id)) AS CountOfLoans
    FROM LoanDataAligned 
    WHERE member_id = 319 
    GROUP BY EffectiveDate, TerminationDate
    ORDER BY EffectiveDate
 ;

EffectiveDate TerminationDate TotalFundedAmount     LargestFundedAmount   GradeLowest          CountOfLoans
------------- --------------- --------------------- --------------------- -------------------- ------------
2010-01-01    2011-03-31      18500.00              18500.00              C                    1
2011-04-01    2013-01-31      33500.00              18500.00              C                    2
2013-02-01    2013-08-31      15000.00              15000.00              D                    1
2013-09-01    2014-12-31      24750.00              15000.00              C                    2
2015-01-01    2015-10-31      36750.00              15000.00              A                    3
2015-11-01    2016-04-30      61750.00              25000.00              A                    4
2016-05-01    2016-09-30      46750.00              25000.00              A                    3
2016-10-01    2018-01-31      37000.00              25000.00              A                    2
2018-02-01    2020-11-30      25000.00              25000.00              C                    1

(9 row(s) affected)
</code></pre>

Finally, we can create a ragged column of ids aggregated by time segment. This uses an subquery to pivot the rows to a ragged column by using the "FOR XML PATH" output. 

This can answer questions like this one from StackOverflow: [Date Range Intersection Splitting in SQL](https://stackoverflow.com/questions/1397877/date-range-intersection-splitting-in-sql/1414494)

<pre><code>
SELECT 
	member_id, EffectiveDate, TerminationDate,

	SUBSTRING ((SELECT ',' + [id] FROM LoanDataAligned AS innerTable 
		WHERE 
			innerTable.member_id = LoanDataAligned.member_id 
			AND (innerTable.EffectiveDate = LoanDataAligned.EffectiveDate) 
			AND (innerTable.TerminationDate = LoanDataAligned.TerminationDate)
		ORDER BY id
		FOR XML PATH ('')), 2, 999999999999999) AS IdList

 FROM LoanDataAligned 
 WHERE member_id = 319 
 GROUP BY member_id, EffectiveDate, TerminationDate
 ORDER BY EffectiveDate
</code></pre>

<pre><code>
member_id            EffectiveDate TerminationDate IdList
-------------------- ------------- --------------- -----------------------------------
319                  2010-01-01    2011-03-31      474548
319                  2011-04-01    2013-01-31      474548,707917
319                  2013-02-01    2013-08-31      707917
319                  2013-09-01    2014-12-31      707917,7338296
319                  2015-01-01    2015-10-31      37227561,707917,7338296
319                  2015-11-01    2016-04-30      37227561,65413538,707917,7338296
319                  2016-05-01    2016-09-30      37227561,65413538,7338296
319                  2016-10-01    2018-01-31      37227561,65413538
319                  2018-02-01    2020-11-30      65413538
</code></pre>

