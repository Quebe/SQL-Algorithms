CREATE OR ALTER PROCEDURE dbo.[DateSegments_AlignWithinTable]
	@tableName AS VARCHAR (0120),
	@keyFieldList AS VARCHAR (0240),
	@nonkeyFieldList AS VARCHAR (0240),
	@effectiveDateFieldName AS VARCHAR (0120),
	@terminationDateFieldName AS VARCHAR (0120)
	
AS
	BEGIN 
		-- Author: Dennis Quebe (https://github.com/quebe)
		-- Licensed under MIT Open Source

		-- THE GOAL IS TO HAVE SEGMENTS BREAK EQUALLY ACROSS THE PARTITION SO THAT THE DATA CAN BE EASILY AGGREGATED
		-- CREATE A WORKING DATA SET FROM ORIGINAL THAT CAN BE MODIFIED, ADD A ROW NUMBER TO KEEP TRACK OF THE SPLITS 
		-- RETURNS: { KEY FIELDS } | { NON-KEY FIELDS } | { EFFECTIVE DATE } | { TERMINATION DATE }

		-- CREATE UNIQUE HASH FIELD FOR AGGREGATE 
		DECLARE @hashFields AS VARCHAR (0360); 
		SET @hashFields = @keyFieldList;
		SET @hashFields = REPLACE (@keyFieldList, ',', ') + ''|'' + LTRIM (');
		SET @hashFields = 'LTRIM (' + @hashFields + ')';
		
		DECLARE @prefixKeyFields AS VARCHAR (0999);
		SET @prefixKeyFields = REPLACE (@keyFieldList, ', ', ','); -- CLEAN UP SPACING FOR NEXT REPLACE STATEMENT
		SET @prefixKeyFields = 'CurrentSegment.' + REPLACE (@prefixKeyFields, ',', ', CurrentSegment.');
		
		DECLARE @prefixNonkeyFields AS VARCHAR (0999);
		SET @prefixNonkeyFields = REPLACE (@nonkeyFieldList, ', ', ','); -- CLEAN UP SPACING FOR NEXT REPLACE STATEMENT
		SET @prefixNonkeyFields = 'CurrentSegment.' + REPLACE (@prefixNonkeyFields, ',', ', CurrentSegment.');


		-- CREATE ALIGNMENT WORKING TABLE
		DECLARE @alignmentWorkingTableScript AS VARCHAR (MAX); 
		SET @alignmentWorkingTableScript = 'SELECT '; 
		SET @alignmentWorkingTableScript = @alignmentWorkingTableScript + '  ROW_NUMBER () OVER (ORDER BY ' + @keyFieldList + ', ' + @effectiveDateFieldName + ') AS RowNumber, '; -- ORIGINAL ROW MARKER
		SET @alignmentWorkingTableScript = @alignmentWorkingTableScript + '  CAST (1 AS INT) AS InstanceId, '; -- MODIFIED OR CREATED INSTANCE ID FOR SEQUENCING 
		SET @alignmentWorkingTableScript = @alignmentWorkingTableScript + '  ROW_NUMBER () OVER (PARTITION BY ' + @keyFieldList + ' ORDER BY ';
		IF (LEN (@nonkeyFieldList) > 0) SET @alignmentWorkingTableScript = @alignmentWorkingTableScript  + @nonkeyFieldList + ', ';
		SET @alignmentWorkingTableScript = @alignmentWorkingTableScript + @effectiveDateFieldName + ') AS SequenceNumber, '; -- ORIGINAL ROW MARKER
		SET @alignmentWorkingTableScript = @alignmentWorkingTableScript + @keyFieldList + ', '; 
		IF (LEN (@nonkeyFieldList) > 0) SET @alignmentWorkingTableScript = @alignmentWorkingTableScript  + @nonkeyFieldList + ', ';
		SET @alignmentWorkingTableScript = @alignmentWorkingTableScript  + 'HASHBYTES (''SHA1'', ' + @hashFields + ') AS AlignAggregateKey, ';
		SET @alignmentWorkingTableScript = @alignmentWorkingTableScript  + 'CAST (' + @effectiveDateFieldName + ' AS DATE) AS EffectiveDate, ';
		SET @alignmentWorkingTableScript = @alignmentWorkingTableScript  + 'CAST (' + @terminationDateFieldName + ' AS DATE) AS TerminationDate ';
		SET @alignmentWorkingTableScript = @alignmentWorkingTableScript  + '  INTO #alignmentWorkingTable ';
		SET @alignmentWorkingTableScript = @alignmentWorkingTableScript  + '  FROM ' + @tableName;
		SET @alignmentWorkingTableScript = @alignmentWorkingTableScript + '; ';

		-- NOW THERE ARE SEVERAL USE CASES WHICH REQUIRE BREAKING SEGMENTS AND CREATING NEW ONES
		-- UMBRELLA SEGMENTS AND OVERLAP SEGMENTS

		-- CASE 1: UMBRELLA SEGMENTS
		-- THE FIRST IS WHEN OTHER SEGMENTS ARE FULLY CONTAINED WITHIN EACH OTHER 
		-- WE WANT TO FIND THOSE SUPER SEGMENTS AND BREAK THEM INTO 3 SEPARATE SEGMENTS 
		--  1:      |---------------------------|
		--  2:          |MIN             MAX|        
		--  RESULT: |---|-------------------|---|

		-- WE REPEAT THIS PROCESS UNTIL ALL SEGMENTS ARE BROKEN AND ARE ONLY OVERLAPS		

		DECLARE @umbrellaProcessScript AS VARCHAR (MAX); 
		SET @umbrellaProcessScript  = '';

		SET @umbrellaProcessScript  = @umbrellaProcessScript + '		DECLARE @umbrella_updated AS INT; ';
		SET @umbrellaProcessScript  = @umbrellaProcessScript + '		SET @umbrella_updated = -1; ';

		SET @umbrellaProcessScript  = @umbrellaProcessScript + '		WHILE (@umbrella_updated != 0) ';
		SET @umbrellaProcessScript  = @umbrellaProcessScript + '			BEGIN ';
		SET @umbrellaProcessScript  = @umbrellaProcessScript + '				/* IDENTIFY UMBRELLA SEGMENTS TO WORK WITH AND SLOWLY START SLICING THE ENDS OFF OF THEM TO MAKE NEW SEGMENTS */';
		SET @umbrellaProcessScript  = @umbrellaProcessScript + '				IF (OBJECT_ID (''tempdb..#alignment_umbrella'') IS NOT NULL) DROP TABLE #alignment_umbrella; ';
		SET @umbrellaProcessScript  = @umbrellaProcessScript + '				SELECT ';
		SET @umbrellaProcessScript  = @umbrellaProcessScript + '							alignment_umbrella.RowNumber, ';
		SET @umbrellaProcessScript  = @umbrellaProcessScript + '							MIN (alignment_child.EffectiveDate) AS EffectiveDate, ';
		SET @umbrellaProcessScript  = @umbrellaProcessScript + '							MAX (alignment_child.TerminationDate) AS TerminationDate';
		SET @umbrellaProcessScript  = @umbrellaProcessScript + '						INTO #alignment_umbrella';
		SET @umbrellaProcessScript  = @umbrellaProcessScript + '						FROM ';
		SET @umbrellaProcessScript  = @umbrellaProcessScript + '							#alignmentWorkingTable AS alignment_umbrella ';
		SET @umbrellaProcessScript  = @umbrellaProcessScript + '								JOIN #alignmentWorkingTable AS alignment_child ';
		SET @umbrellaProcessScript  = @umbrellaProcessScript + '									ON alignment_umbrella.AlignAggregateKey = alignment_child.AlignAggregateKey /* SAME KEY SET */ ';
		SET @umbrellaProcessScript  = @umbrellaProcessScript + '									AND alignment_umbrella.RowNumber <> alignment_child.RowNumber /* DIFFERENT ROW */ ';
		SET @umbrellaProcessScript  = @umbrellaProcessScript + '									AND alignment_umbrella.EffectiveDate < alignment_child.EffectiveDate ';
		SET @umbrellaProcessScript  = @umbrellaProcessScript + '									AND alignment_umbrella.TerminationDate > alignment_child.TerminationDate ';
		SET @umbrellaProcessScript  = @umbrellaProcessScript + '						GROUP BY alignment_umbrella.RowNumber; '

		SET @umbrellaProcessScript  = @umbrellaProcessScript + '				/* CREATE THE MIDDLE SPLIT ROW */ ';
		SET @umbrellaProcessScript  = @umbrellaProcessScript + '				INSERT INTO #alignmentWorkingTable ';
		SET @umbrellaProcessScript  = @umbrellaProcessScript + '				SELECT ';
		SET @umbrellaProcessScript  = @umbrellaProcessScript + '						CurrentSegment.RowNumber, CAST (2 AS INT) AS InstanceId, CurrentSegment.SequenceNumber, ';
		SET @umbrellaProcessScript  = @umbrellaProcessScript + @prefixKeyFields + ', ' + @prefixNonkeyFields + ', '; 
		SET @umbrellaProcessScript  = @umbrellaProcessScript + '						CurrentSegment.AlignAggregateKey, Umbrella.EffectiveDate, Umbrella.TerminationDate ';
		SET @umbrellaProcessScript  = @umbrellaProcessScript + '					FROM #alignmentWorkingTable AS CurrentSegment ';
		SET @umbrellaProcessScript  = @umbrellaProcessScript + '						JOIN #alignment_umbrella AS Umbrella ON CurrentSegment.RowNumber = Umbrella.RowNumber ';
		SET @umbrellaProcessScript  = @umbrellaProcessScript + '					; ';

		SET @umbrellaProcessScript  = @umbrellaProcessScript + '				/* CREATE THE LAST SPLIT ROW */ ';
		SET @umbrellaProcessScript  = @umbrellaProcessScript + '				INSERT INTO #alignmentWorkingTable ';
		SET @umbrellaProcessScript  = @umbrellaProcessScript + '				SELECT ';
		SET @umbrellaProcessScript  = @umbrellaProcessScript + '						CurrentSegment.RowNumber, CAST (3 AS INT) AS InstanceId, CurrentSegment.SequenceNumber, ';
		SET @umbrellaProcessScript  = @umbrellaProcessScript + @prefixKeyFields + ', ' + @prefixNonkeyFields + ', ';
		SET @umbrellaProcessScript  = @umbrellaProcessScript + '						CurrentSegment.AlignAggregateKey, ';
		SET @umbrellaProcessScript  = @umbrellaProcessScript + '						DATEADD (DD, 1, Umbrella.TerminationDate) AS EffectiveDate,';
		SET @umbrellaProcessScript  = @umbrellaProcessScript + '						CurrentSegment.TerminationDate';
		SET @umbrellaProcessScript  = @umbrellaProcessScript + '					FROM #alignmentWorkingTable AS CurrentSegment';
		SET @umbrellaProcessScript  = @umbrellaProcessScript + '						JOIN #alignment_umbrella AS Umbrella ON CurrentSegment.RowNumber = Umbrella.RowNumber';
		SET @umbrellaProcessScript  = @umbrellaProcessScript + '						WHERE CurrentSegment.InstanceId = 1 /* ONLY REPLICATE THE FIRST ORIGINAL INSTANCE INTO THE 3 SPLIT */';
		SET @umbrellaProcessScript  = @umbrellaProcessScript + '					;';

		SET @umbrellaProcessScript  = @umbrellaProcessScript + '				/* UPDATE THE ORIGINAL ROW */';
		SET @umbrellaProcessScript  = @umbrellaProcessScript + '				UPDATE #alignmentWorkingTable';
		SET @umbrellaProcessScript  = @umbrellaProcessScript + '					SET TerminationDate = DATEADD (DD, -1, Umbrella.EffectiveDate) ';
		SET @umbrellaProcessScript  = @umbrellaProcessScript + '					FROM #alignmentWorkingTable AS CurrentSegment';
		SET @umbrellaProcessScript  = @umbrellaProcessScript + '						JOIN #alignment_umbrella AS Umbrella ON CurrentSegment.RowNumber = Umbrella.RowNumber';
		SET @umbrellaProcessScript  = @umbrellaProcessScript + '						WHERE CurrentSegment.InstanceId = 1 /* ONLY UPDATE THE ORIGINAL ROW */';
		SET @umbrellaProcessScript  = @umbrellaProcessScript + '				;';

		SET @umbrellaProcessScript  = @umbrellaProcessScript + '				/* FIX THE ROW ID AND INSTANCE ID */ ';
		SET @umbrellaProcessScript  = @umbrellaProcessScript + '				WITH alignment_cte AS (SELECT ROW_NUMBER () OVER (ORDER BY /* KEY FIELD LIST, EFFECTIVE DATE */ ' + @keyFieldList + ', EffectiveDate) AS RowNumberNew, * FROM #alignmentWorkingTable) '; 
		SET @umbrellaProcessScript  = @umbrellaProcessScript + '				UPDATE alignment_cte SET RowNumber = RowNumberNew, InstanceId = 1;';
		SET @umbrellaProcessScript  = @umbrellaProcessScript + '				SELECT @umbrella_updated = COUNT (1) FROM #alignment_umbrella;';
		SET @umbrellaProcessScript  = @umbrellaProcessScript + '			END ';


		-- CASE 2: LEFT OVERLAP SEGMENTS

		-- THE FIRST IS WHEN OTHER SEGMENTS OVERLAP THE TERMINATION DATE WITH THEIR EFFECTIVE DATES
		-- WE WANT TO FIND THOSE SEGMENTS AND BREAK THEM INTO TWO SEGMENTS 
		-- WE GET THE INTERSECTION OF THE MINIMUM OVERLAPING EFFECTIVE DATE AND KEEP LOOPING
		--  1:      |---------------|
		--  2:                |MIN-->
		--  RESULT: |---------|-----|

		-- WE REPEAT THIS PROCESS UNTIL ALL SEGMENTS ARE BROKEN AND ARE ONLY OVERLAPS

		DECLARE @leftOverlapProcessScript AS VARCHAR (MAX); 
		SET @leftOverlapProcessScript = ''; 
		SET @leftOverlapProcessScript = @leftOverlapProcessScript + '';

		SET @leftOverlapProcessScript = @leftOverlapProcessScript + '		DECLARE @overlap_updated AS INT; ';
		SET @leftOverlapProcessScript = @leftOverlapProcessScript + '		SET @overlap_updated = -1;';
		SET @leftOverlapProcessScript = @leftOverlapProcessScript + '		WHILE (@overlap_updated != 0) ';
		SET @leftOverlapProcessScript = @leftOverlapProcessScript + '			BEGIN ';
		SET @leftOverlapProcessScript = @leftOverlapProcessScript + '				IF (OBJECT_ID (''tempdb..#alignmentWorkingTable_overlap_case2'') IS NOT NULL) DROP TABLE #alignmentWorkingTable_overlap_case2;';
		SET @leftOverlapProcessScript = @leftOverlapProcessScript + '				SELECT ';
		SET @leftOverlapProcessScript = @leftOverlapProcessScript + '						alignment_overlap.RowNumber, ';
		SET @leftOverlapProcessScript = @leftOverlapProcessScript + '						MIN (alignment_child.EffectiveDate) AS overap_EffectiveDate';
		SET @leftOverlapProcessScript = @leftOverlapProcessScript + '					INTO #alignmentWorkingTable_overlap_case2';
		SET @leftOverlapProcessScript = @leftOverlapProcessScript + '					FROM ';
		SET @leftOverlapProcessScript = @leftOverlapProcessScript + '						#alignmentWorkingTable AS alignment_overlap';
		SET @leftOverlapProcessScript = @leftOverlapProcessScript + '							JOIN #alignmentWorkingTable AS alignment_child';
		SET @leftOverlapProcessScript = @leftOverlapProcessScript + '								ON alignment_overlap.AlignAggregateKey = alignment_child.AlignAggregateKey /* SAME KEY SET */';
		SET @leftOverlapProcessScript = @leftOverlapProcessScript + '								AND alignment_overlap.RowNumber <> alignment_child.RowNumber  /* DIFFERENT ROW */';
		SET @leftOverlapProcessScript = @leftOverlapProcessScript + '								AND alignment_child.EffectiveDate > alignment_overlap.EffectiveDate /* NOT SAME EFFECTIVE DATE (DON''T NEED TO SPLIT THESE) */';
		SET @leftOverlapProcessScript = @leftOverlapProcessScript + '								AND alignment_child.EffectiveDate <= alignment_overlap.TerminationDate 						';
		SET @leftOverlapProcessScript = @leftOverlapProcessScript + '					GROUP BY alignment_overlap.RowNumber ;';
		
		SET @leftOverlapProcessScript = @leftOverlapProcessScript + '				/* CREATE THE SPLIT ROW */';
		SET @leftOverlapProcessScript = @leftOverlapProcessScript + '				INSERT INTO #alignmentWorkingTable';
		SET @leftOverlapProcessScript = @leftOverlapProcessScript + '				SELECT ';
		SET @leftOverlapProcessScript = @leftOverlapProcessScript + '						CurrentSegment.RowNumber, CAST (2 AS INT) AS InstanceId, CurrentSegment.SequenceNumber, ';
		SET @leftOverlapProcessScript = @leftOverlapProcessScript + @keyFieldList + ', ' + @nonkeyFieldList + ', ';
		SET @leftOverlapProcessScript = @leftOverlapProcessScript + '						CurrentSegment.AlignAggregateKey, ';
		SET @leftOverlapProcessScript = @leftOverlapProcessScript + '						Overlap.overap_EffectiveDate AS EffectiveDate,';
		SET @leftOverlapProcessScript = @leftOverlapProcessScript + '						CurrentSegment.TerminationDate';
		SET @leftOverlapProcessScript = @leftOverlapProcessScript + '					FROM #alignmentWorkingTable AS CurrentSegment';
		SET @leftOverlapProcessScript = @leftOverlapProcessScript + '						JOIN #alignmentWorkingTable_overlap_case2 AS Overlap ON CurrentSegment.RowNumber = Overlap.RowNumber';
		SET @leftOverlapProcessScript = @leftOverlapProcessScript + '					;';

		SET @leftOverlapProcessScript = @leftOverlapProcessScript + '				/* UPDATE THE ORIGINAL ROW */';
		SET @leftOverlapProcessScript = @leftOverlapProcessScript + '				UPDATE #alignmentWorkingTable ';
		SET @leftOverlapProcessScript = @leftOverlapProcessScript + '					SET TerminationDate = DATEADD (DD, -1, #alignmentWorkingTable_overlap_case2.overap_EffectiveDate)';
		SET @leftOverlapProcessScript = @leftOverlapProcessScript + '					FROM #alignmentWorkingTable ';
		SET @leftOverlapProcessScript = @leftOverlapProcessScript + '						JOIN #alignmentWorkingTable_overlap_case2 ';
		SET @leftOverlapProcessScript = @leftOverlapProcessScript + '						ON #alignmentWorkingTable.RowNumber = #alignmentWorkingTable_overlap_case2.RowNumber';
		SET @leftOverlapProcessScript = @leftOverlapProcessScript + '					WHERE #alignmentWorkingTable.InstanceId = 1 /* ONLY UPDATE THE ORIGINAL ROW */ ';
		SET @leftOverlapProcessScript = @leftOverlapProcessScript + '					;';

		SET @leftOverlapProcessScript = @leftOverlapProcessScript + '				/* FIX THE ROW ID AND INSTANCE ID */';
		SET @leftOverlapProcessScript = @leftOverlapProcessScript + '				WITH alignment_cte AS (SELECT ROW_NUMBER () OVER (ORDER BY /* KEY FIELD LIST, EFFECTIVE DATE */ ' + @keyFieldList + ', EffectiveDate) AS RowNumberNew, * FROM #alignmentWorkingTable) ';
		SET @leftOverlapProcessScript = @leftOverlapProcessScript + '				UPDATE alignment_cte SET RowNumber = RowNumberNew, InstanceId = 1;';
		SET @leftOverlapProcessScript = @leftOverlapProcessScript + '				SELECT @overlap_updated = COUNT (1) FROM #alignmentWorkingTable_overlap_case2;';
		SET @leftOverlapProcessScript = @leftOverlapProcessScript + '			END ';
	

		-- CASE 3: RIGHT OVERLAP SEGMENTS

		-- THE FIRST IS WHEN OTHER SEGMENTS OVERLAP THE EFFECTIVE DATE WITH THEIR TERMINATION DATES
		-- WE WANT TO FIND THOSE SEGMENTS AND BREAK THEM INTO TWO SEGMENTS 
		-- WE GET THE INTERSECTION OF THE MAXIMUM OVERLAPING TERMINATION DATE AND KEEP LOOPING
		--          |---------------|
		--          <----MAX|
		--  RESULT: |-------|-------|

		-- WE REPEAT THIS PROCESS UNTIL ALL SEGMENTS ARE BROKEN AND ARE ONLY OVERLAPS

		DECLARE @rightOverlapProcessScript AS VARCHAR (MAX); 
		SET @rightOverlapProcessScript = ''; 
		SET @rightOverlapProcessScript = @rightOverlapProcessScript + '';
		
		SET @rightOverlapProcessScript = @rightOverlapProcessScript + '		SET @overlap_updated = -1; ';
		SET @rightOverlapProcessScript = @rightOverlapProcessScript + '		WHILE (@overlap_updated != 0) ';
		SET @rightOverlapProcessScript = @rightOverlapProcessScript + '			BEGIN ';
		SET @rightOverlapProcessScript = @rightOverlapProcessScript + '				IF (OBJECT_ID (''tempdb..#alignment_overlap_case3'') IS NOT NULL) DROP TABLE #alignment_overlap_case3;';
	
		SET @rightOverlapProcessScript = @rightOverlapProcessScript + '				SELECT ';
		SET @rightOverlapProcessScript = @rightOverlapProcessScript + '						alignment_overlap.RowNumber, ';
		SET @rightOverlapProcessScript = @rightOverlapProcessScript + '						MAX (alignment_child.TerminationDate) AS overap_TerminationDate';
		SET @rightOverlapProcessScript = @rightOverlapProcessScript + '					INTO #alignment_overlap_case3';
		SET @rightOverlapProcessScript = @rightOverlapProcessScript + '					FROM ';
		SET @rightOverlapProcessScript = @rightOverlapProcessScript + '						#alignmentWorkingTable AS alignment_overlap';
		SET @rightOverlapProcessScript = @rightOverlapProcessScript + '							JOIN #alignmentWorkingTable AS alignment_child';
		SET @rightOverlapProcessScript = @rightOverlapProcessScript + '								ON alignment_overlap.AlignAggregateKey = alignment_child.AlignAggregateKey /* SAME KEY SET */';
		SET @rightOverlapProcessScript = @rightOverlapProcessScript + '								AND alignment_overlap.RowNumber <> alignment_child.RowNumber  /* DIFFERENT ROW */';
		SET @rightOverlapProcessScript = @rightOverlapProcessScript + '								AND alignment_child.TerminationDate < alignment_overlap.TerminationDate /* NOT SAME TERMINATION DATE (DON''T NEED TO SPLIT THESE) */ ';
		SET @rightOverlapProcessScript = @rightOverlapProcessScript + '								AND alignment_child.TerminationDate >= alignment_overlap.EffectiveDate ';
		SET @rightOverlapProcessScript = @rightOverlapProcessScript + '					GROUP BY  alignment_overlap.RowNumber';
		SET @rightOverlapProcessScript = @rightOverlapProcessScript + '					;';
		
		SET @rightOverlapProcessScript = @rightOverlapProcessScript + '				/* CREATE THE SPLIT ROW */';
		SET @rightOverlapProcessScript = @rightOverlapProcessScript + '				INSERT INTO #alignmentWorkingTable';
		SET @rightOverlapProcessScript = @rightOverlapProcessScript + '				SELECT ';
		SET @rightOverlapProcessScript = @rightOverlapProcessScript + '						CurrentSegment.RowNumber, CAST (2 AS INT) AS InstanceId, CurrentSegment.SequenceNumber, ';
		SET @rightOverlapProcessScript = @rightOverlapProcessScript + @prefixKeyFields + ', ' + @prefixNonkeyFields + ', ';
		SET @rightOverlapProcessScript = @rightOverlapProcessScript + '                     CurrentSegment.AlignAggregateKey, ';
		SET @rightOverlapProcessScript = @rightOverlapProcessScript + '						DATEADD (DD, 1, Overlap.overap_TerminationDate) AS EffectiveDate,';
		SET @rightOverlapProcessScript = @rightOverlapProcessScript + '						CurrentSegment.TerminationDate';
		SET @rightOverlapProcessScript = @rightOverlapProcessScript + '					FROM #alignmentWorkingTable AS CurrentSegment';
		SET @rightOverlapProcessScript = @rightOverlapProcessScript + '						JOIN #alignment_overlap_case3 AS Overlap ON CurrentSegment.RowNumber = Overlap.RowNumber';
		SET @rightOverlapProcessScript = @rightOverlapProcessScript + '					;';
			
		SET @rightOverlapProcessScript = @rightOverlapProcessScript + '				/* UPDATE THE ORIGINAL ROW */';
		SET @rightOverlapProcessScript = @rightOverlapProcessScript + '				UPDATE #alignmentWorkingTable ';
		SET @rightOverlapProcessScript = @rightOverlapProcessScript + '					SET TerminationDate = #alignment_overlap_case3.overap_TerminationDate';
		SET @rightOverlapProcessScript = @rightOverlapProcessScript + '					FROM #alignmentWorkingTable JOIN #alignment_overlap_case3 ON #alignmentWorkingTable.RowNumber = #alignment_overlap_case3.RowNumber';
		SET @rightOverlapProcessScript = @rightOverlapProcessScript + '					WHERE #alignmentWorkingTable.InstanceId = 1 /* ONLY UPDATE THE ORIGINAL ROW */';
		SET @rightOverlapProcessScript = @rightOverlapProcessScript + '					;';

		SET @rightOverlapProcessScript = @rightOverlapProcessScript + '				/* FIX THE ROW ID AND INSTANCE ID */';
		SET @rightOverlapProcessScript = @rightOverlapProcessScript + '				WITH alignment_cte AS (SELECT ROW_NUMBER () OVER (ORDER BY /* KEY FIELD LIST, EFFECTIVE DATE */ ' + @keyFieldList + ', EffectiveDate) AS RowNumberNew, * FROM #alignmentWorkingTable) ';
		SET @rightOverlapProcessScript = @rightOverlapProcessScript + '				UPDATE alignment_cte SET RowNumber = RowNumberNew, InstanceId = 1;';
		SET @rightOverlapProcessScript = @rightOverlapProcessScript + '				SELECT @overlap_updated = COUNT (1) FROM #alignment_overlap_case3;';
		SET @rightOverlapProcessScript = @rightOverlapProcessScript + '			END ';
	
		-- RETURN TABLE SCRIPT 		
		DECLARE @returnTableScript AS NVARCHAR (MAX); 

		SET @returnTableScript = 'SELECT ';
		SET @returnTableScript = @returnTableScript  + @keyFieldList + ', ';
		IF (LEN (@nonkeyFieldList) > 0) SET @returnTableScript = @returnTableScript  + @nonkeyFieldList + ', ';
		SET @returnTableScript = @returnTableScript + 'EffectiveDate AS ' + @effectiveDateFieldName + ', TerminationDate AS ' + @terminationDateFieldName + ' ';
		SET @returnTableScript = @returnTableScript + '  FROM #alignmentWorkingTable'
		SET @returnTableScript = @returnTableScript + '; ';

		-- EXECUTE DYNAMIC SQL 
		-- PRINT @alignmentWorkingTableScript + @umbrellaProcessScript + @leftOverlapProcessScript + @rightOverlapProcessScript + @returnTableScript;
		EXECUTE (@alignmentWorkingTableScript + @umbrellaProcessScript + @leftOverlapProcessScript + @rightOverlapProcessScript + @returnTableScript) WITH RESULT SETS UNDEFINED; 

	END

;