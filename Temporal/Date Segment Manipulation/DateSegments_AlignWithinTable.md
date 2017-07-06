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

The number of segments can be reduced using the "DateSegment_MergeByGrow" stored procedure to produce the following result:

<pre><code>
"A":                                          |--------|
"B":       |--------------| 
"C":                      |-------------------|
</code></pre>


## Examples

### A. Example

