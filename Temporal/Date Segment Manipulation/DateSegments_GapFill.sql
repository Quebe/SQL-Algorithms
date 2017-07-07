CREATE PROCEDURE dbo.[DateSegments_GapFill]

	@tableName AS VARCHAR (0120),
	@keyFieldList AS VARCHAR (0240),
	@nonkeyFieldList AS VARCHAR (0240),
	@effectiveDateFieldName AS VARCHAR (0120),
	@terminationDateFieldName AS VARCHAR (0120),
	@copyNonkeyFieldValues AS BIT, -- COPY THE VALUES FROM A REAL RECORD OR SET TO NULL
	@includeRealIndicator AS BIT -- INCLUDE AN INDICATOR IN THE RESULT SET FOR REAL/FAKE RECORD 
	
AS
	BEGIN 
		-- Author: Dennis Quebe (https://github.com/Quebe)
		-- Licensed under MIT Open Source

		-- THIS PROCEDURE FILLS IN FAKE SEGMENTS IN BETWEEN EXISTING REAL SEGMENTS 
		-- TO CREATE A CONTIGUOUS SET OF DATE SEGMENTS FOR A PARTITION 
	
		-- CREATE UNIQUE HASH FIELD FOR AGGREGATE 
		DECLARE @hashFields AS VARCHAR (0360); 
		SET @hashFields = @keyFieldList;
		SET @hashFields = REPLACE (@keyFieldList, ',', ') + ''|'' + LTRIM (');
		SET @hashFields = 'LTRIM (' + @hashFields + ')';
		
		-- SET UP PREFIXED FIELDS FOR SCRIPTS 
		DECLARE @prefixKeyFields AS VARCHAR (0999);
		SET @prefixKeyFields = REPLACE (@keyFieldList, ', ', ','); -- CLEAN UP SPACING FOR NEXT REPLACE STATEMENT
		SET @prefixKeyFields = 'CurrentSegment.' + REPLACE (@prefixKeyFields, ',', ', CurrentSegment.');


		DECLARE @prefixCarryFields AS VARCHAR (0999);
		SET @prefixCarryFields = REPLACE (@nonkeyFieldList, ', ', ','); -- CLEAN UP SPACING FOR NEXT REPLACE STATEMENT
		IF (@copyNonkeyFieldValues = 1) SET @prefixCarryFields = 'CurrentSegment.' + REPLACE (@prefixCarryFields, ',', ', CurrentSegment.');
		ELSE SET @prefixCarryFields = 'NULL AS ' + REPLACE (@prefixCarryFields, ',', ', NULL AS ');
		

		-- WORKING TABLE SCRIPT 
		DECLARE @workingTableScript AS NVARCHAR (MAX); 
		SET @workingTableScript = ''
		SET @workingTableScript = @workingTableScript  + 'SELECT ';
		SET @workingTableScript = @workingTableScript  + @keyFieldList + ', ';
		IF (LEN (@nonkeyFieldList) > 0) SET @workingTableScript = @workingTableScript  + @nonkeyFieldList + ', ';
		SET @workingTableScript = @workingTableScript;
		SET @workingTableScript = @workingTableScript  + 'HASHBYTES (''SHA1'', ' + @hashFields + ') AS GapFillAggregateKey, ';
		SET @workingTableScript = @workingTableScript  + 'CAST (' + @effectiveDateFieldName + ' AS DATE) AS EffectiveDate, ';
		SET @workingTableScript = @workingTableScript  + 'CAST (' + @terminationDateFieldName + ' AS DATE) AS TerminationDate ';
		IF (@includeRealIndicator = 1) SET @workingTableScript = @workingTableScript + ', CAST (1 AS BIT) AS RealRecord ';
		SET @workingTableScript = @workingTableScript  + '  INTO #gapFillWorkingTable ';
		SET @workingTableScript = @workingTableScript  + '  FROM ' + @tableName + ' /* RIGHT JOIN NULL */ ';
		SET @workingTableScript = @workingTableScript + '; ';

		-- PRINT @workingTableScript;

		-- AFTER TESTING, WE NEED TO RESTRUCTURE OUR WORKING TABLE SCRIPT INTO A SPECIALIZED VERSION 
		-- THAT CREATES THE BASE TABLE WITH NULLS AND THEN INSERTS THE RECORDS, THIS IS TO SUPPORT NULLS IN 
		-- THE COLUMNS, OTHERWISE, TEMP TABLES ARE BASED ON FIRST ROW OF DATA FOR NULL SUPPORT

		SET @workingTableScript = 
			REPLACE (@workingTableScript, '/* RIGHT JOIN NULL */', ' RIGHT JOIN (SELECT NULL AS EmptyColumn) AS EmptyTable ON (1 = 0) ')
			+ ' TRUNCATE TABLE #gapFillWorkingTable; ' 
			+ ' INSERT INTO #gapFillWorkingTable ' + REPLACE (@workingTableScript, 'INTO #gapFillWorkingTable', '');

		-- PRINT @workingTableScript;

		
		-- INSERT FRONT GAP RECORDS (FAKE)
		DECLARE @frontLoadScript AS NVARCHAR (MAX);
		SET @frontLoadScript = 'INSERT INTO #gapFillWorkingTable ';
		SET @frontLoadScript = @frontLoadScript + 'SELECT ';
		SET @frontLoadScript = @frontLoadScript + @prefixKeyFields + ', ';
		IF (LEN (@nonkeyFieldList) > 0) SET @frontLoadScript = @frontLoadScript  + @prefixCarryFields + ', ';
		SET @frontLoadScript = @frontLoadScript + 'CurrentSegment.GapFillAggregateKey, ';
		SET @frontLoadScript = @frontLoadScript + 'ISNULL (DATEADD (DD, 1, MAX (PreviousSegment.TerminationDate)), ''01/01/0001'') AS EffectiveDate, ';
		SET @frontLoadScript = @frontLoadScript + 'DATEADD (DD, -1, CurrentSegment.EffectiveDate) AS TerminationDate';
		IF (@includeRealIndicator = 1) SET @frontLoadScript = @frontLoadScript + ', 0 AS RealRecord ';
		SET @frontLoadScript = @frontLoadScript + ' FROM ';
		SET @frontLoadScript = @frontLoadScript + '    #gapFillWorkingTable AS CurrentSegment ';
		SET @frontLoadScript = @frontLoadScript + '				LEFT JOIN #gapFillWorkingTable AS PreviousSegment';
		SET @frontLoadScript = @frontLoadScript + '				ON CurrentSegment.GapFillAggregateKey = PreviousSegment.GapFillAggregateKey';
		SET @frontLoadScript = @frontLoadScript + '				AND CurrentSegment.EffectiveDate > PreviousSegment.TerminationDate';
		SET @frontLoadScript = @frontLoadScript + '  GROUP BY ';
		SET @frontLoadScript = @frontLoadScript + @prefixKeyFields + ', ';
		IF ((LEN (@nonkeyFieldList) > 0) AND (@copyNonkeyFieldValues = 1)) SET @frontLoadScript = @frontLoadScript + @prefixCarryFields + ', ';
		SET @frontLoadScript = @frontLoadScript + '    CurrentSegment.GapFillAggregateKey, CurrentSegment.EffectiveDate';
		SET @frontLoadScript = @frontLoadScript + '  HAVING DATEDIFF (DD, ISNULL (MAX (PreviousSegment.TerminationDate), ''01/01/0001''), CurrentSegment.EffectiveDate) > 1';
		SET @frontLoadScript = @frontLoadScript + '; ';
		
		-- INSERT BACK GAP RECORDS 
		DECLARE @backLoadScript AS NVARCHAR (MAX);
		SET @backLoadScript = 'INSERT INTO #gapFillWorkingTable ';
		SET @backLoadScript = @backLoadScript + 'SELECT ';
		SET @backLoadScript = @backLoadScript + @prefixKeyFields + ', ';
		IF (LEN (@nonkeyFieldList) > 0) SET @backLoadScript = @backLoadScript  + @prefixCarryFields + ', ';
		SET @backLoadScript = @backLoadScript + 'CurrentSegment.GapFillAggregateKey, ';
		SET @backLoadScript = @backLoadScript + 'DATEADD (DD, 1, MAX (CurrentSegment.TerminationDate)) AS EffectiveDate, ';
		SET @backLoadScript = @backLoadScript + 'CAST (''12/31/9999'' AS DATE) AS TerminationDate';
		IF (@includeRealIndicator = 1) SET @backLoadScript = @backLoadScript + ', 0 AS RealRecord ';
		SET @backLoadScript = @backLoadScript + ' FROM ';
		SET @backLoadScript = @backLoadScript + '    #gapFillWorkingTable AS CurrentSegment ';
		SET @backLoadScript = @backLoadScript + '  GROUP BY ';
		SET @backLoadScript = @backLoadScript + @prefixKeyFields + ', ';
		IF ((LEN (@nonkeyFieldList) > 0) AND (@copyNonkeyFieldValues = 1)) SET @backLoadScript = @backLoadScript + @prefixCarryFields + ', ';
		SET @backLoadScript = @backLoadScript + 'CurrentSegment.GapFillAggregateKey ';
		SET @backLoadScript = @backLoadScript + '  HAVING (MAX (CurrentSegment.TerminationDate) < ''12/31/9999'')';
		SET @backLoadScript = @backLoadScript + '; ';

		
		-- RETURN TABLE SCRIPT 		
		DECLARE @returnTableScript AS NVARCHAR (MAX); 
		SET @returnTableScript = 'SELECT ';
		SET @returnTableScript = @returnTableScript  + @keyFieldList + ', ';
		IF (LEN (@nonkeyFieldList) > 0) SET @returnTableScript = @returnTableScript  + @nonkeyFieldList + ', ';
		SET @returnTableScript = @returnTableScript + 'EffectiveDate AS ' + @effectiveDateFieldName + ', TerminationDate AS ' + @terminationDateFieldName + ' ';
		IF (@includeRealIndicator = 1) SET @returnTableScript = @returnTableScript + ', RealRecord ';
		SET @returnTableScript = @returnTableScript + '  FROM #gapFillWorkingTable'
		SET @returnTableScript = @returnTableScript + '; ';
		
		
		-- EXECUTE DYNAMIC SQL 
		-- PRINT @workingTableScript + @frontLoadScript + @backLoadScript + @returnTableScript;
		EXECUTE (@workingTableScript + @frontLoadScript + @backLoadScript + @returnTableScript) WITH RESULT SETS UNDEFINED; 

	END

;