-- PREP SCRIPT FROM SCRATCH 

DROP TABLE LoanData; 
GO


SELECT * INTO LoanData FROM LoanData_Backup;
GO


DELETE FROM LoanData WHERE member_id IS NULL;
UPDATE LoanData SET member_id = RIGHT (CAST (CONVERT (BIGINT, member_id) AS VARCHAR (0020)), LEN (CAST (CONVERT (BIGINT, member_id) AS VARCHAR (0020))) -1);
GO


ALTER TABLE LoanData ADD EffectiveDate DATE NULL;
GO

ALTER TABLE LoanData ADD TerminationDate DATE NULL;
GO 

UPDATE LoanData SET EffectiveDate = PARSE (CAST (issue_d AS CHAR (0020)) AS date);
UPDATE LoanData SET TerminationDate = DATEADD (DAY, -1, DATEADD (MONTH, ISNULL (CAST (SUBSTRING (term, 2, 2) AS INT), 0) + 1, EffectiveDate));
GO

/* CHANGE DATA TYPES FROM NTEXT TO SOMETHING WORKABLE */

ALTER TABLE LoanData ALTER COLUMN [id] VARCHAR (0020);
GO

ALTER TABLE LoanData ALTER COLUMN [grade] VARCHAR (0020);
GO 

ALTER TABLE LoanData ALTER COLUMN [loan_status] VARCHAR (0060);
GO

CREATE CLUSTERED INDEX LoanData_ClusterIdx ON LoanData (member_id, EffectiveDate, TerminationDate);
GO

