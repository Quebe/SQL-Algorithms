CREATE OR ALTER PROCEDURE dbo.[DateSegments_MergeByGrow]

	@tableName AS VARCHAR (0120),
	@fieldList AS VARCHAR (0240),
	@effectiveDateFieldName AS VARCHAR (0120),
	@terminationDateFieldName AS VARCHAR (0120)
--	@destinationTableName AS VARCHAR (0120)

AS

	BEGIN 
		-- MERGES A TABLE OF SEGMENTED DATA BASED ON SAME AGGREGATE FIELDS 
		-- USING A GROW/OVERLAP METHOD AND THEN RETURN THE DISTINCT RECORDS 
		-- BASED ON THE AGGREGATE KEYS 

		-- CREATE UNIQUE HASH FIELD FOR AGGREGATE 
		DECLARE @hashFields AS VARCHAR (0360); 
		SET @hashFields = @fieldList;
		SET @hashFields = REPLACE (@fieldList, ',', ') + ''|'' + LTRIM (');
		SET @hashFields = 'LTRIM (' + @hashFields + ')';


		-- WORKING TABLE SCRIPT 
		DECLARE @workingTableScript AS NVARCHAR (MAX); 
		SET @workingTableScript = ''
		SET @workingTableScript = @workingTableScript  + 'SELECT ';
		SET @workingTableScript = @workingTableScript  + 'ROW_NUMBER () OVER (ORDER BY ' + @fieldList + ') AS RowNumber, ';
		SET @workingTableScript = @workingTableScript  + @fieldList + ', ';
		--SET @workingTableScript = @workingTableScript  + @fieldList + ', ' + @effectiveDateFieldName + ', ' + @terminationDateFieldName + ', ';
		SET @workingTableScript = @workingTableScript  + 'HASHBYTES (''SHA1'', ' + @hashFields + ') AS AggregateKey, ';
		SET @workingTableScript = @workingTableScript  + 'CAST (' + @effectiveDateFieldName + ' AS DATE) AS EffectiveDate, ';
		SET @workingTableScript = @workingTableScript  + 'CAST (' + @terminationDateFieldName + ' AS DATE) AS TerminationDate ';
		SET @workingTableScript = @workingTableScript  + '  INTO #workingTable ';
		SET @workingTableScript = @workingTableScript  + '  FROM ' + @tableName;

		
		-- PROCESS SCRIPT (PROCESSES WORKING TABLE)
		DECLARE @processScript AS NVARCHAR (MAX); 
		SET @processScript = '
		DECLARE @rowsUpdated AS INTEGER;
		SET @rowsUpdated = 1; 
		WHILE (@rowsUpdated > 0) 
			BEGIN 
				UPDATE #workingTable 
							SET 
								EffectiveDate = CASE WHEN (#workingTable.EffectiveDate < ISNULL (OverlapTable.EffectiveDate, #workingTable.EffectiveDate)) THEN #workingTable.EffectiveDate ELSE OverlapTable.EffectiveDate END,
								TerminationDate = CASE WHEN (#workingTable.TerminationDate > ISNULL (OverlapTable.TerminationDate, #workingTable.TerminationDate)) THEN #workingTable.TerminationDate ELSE OverlapTable.TerminationDate END
							FROM 
								#workingTable
									JOIN #workingTable AS OverlapTable
									ON #workingTable.AggregateKey = OverlapTable.AggregateKey -- SAME SEGMENT TYPE
									AND #workingTable.EffectiveDate <= DATEADD (DAY, 1, OverlapTable.TerminationDate) -- OVERLAP SEGMENT
									AND #workingTable.TerminationDate >= DATEADD (DAY, -1, OverlapTable.EffectiveDate) -- OVERLAP SEGMENT
									AND #workingTable.RowNumber <> OverlapTable.RowNumber -- DIFFERENT SEGMENTS 
									AND ((#workingTable.EffectiveDate <> OverlapTable.EffectiveDate) OR (#workingTable.TerminationDate <> OverlapTable.TerminationDate)) -- NOT PERFECT MATCH 
						;

					SET @rowsUpdated = @@ROWCOUNT
				END 
		';


		-- RETURN TABLE SCRIPT 		
		DECLARE @returnTableScript AS NVARCHAR (MAX); 
		-- SET @returnTableScript = 'INSERT INTO ' + @destinationTableName;
		SET @returnTableScript = 'SELECT DISTINCT ';
		SET @returnTableScript = @returnTableScript  + @fieldList + ', ';
		SET @returnTableScript = @returnTableScript + 'EffectiveDate AS ' + @effectiveDateFieldName + ', TerminationDate AS ' + @terminationDateFieldName + ' ';
		SET @returnTableScript = @returnTableScript + '  FROM #workingTable'

		-- EXECUTE DYNAMIC SQL 
		PRINT @workingTableScript + @processScript + @returnTableScript
		EXECUTE (@workingTableScript + @processScript + @returnTableScript) WITH RESULT SETS UNDEFINED; 
	END
;