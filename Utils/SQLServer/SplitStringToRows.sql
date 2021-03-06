-- =====================================================================
-- Author: Fernando Prass | Create date: 05/10/2010
-- Language: T-SQL for SQL Server 2005+
-- Description: Split a string to multiple rows
-- Contact: https://gitlab.com/fernando.prass or https://twitter.com/oFernandoPrass
-- =====================================================================

CREATE FUNCTION dbo.fcSplit
   ( @string varchar(max)
   , @delimitador nvarchar(15)
   )  
RETURNS @array table 
   (ID int identity(1,1)
   ,VALUE nvarchar(max)
   ,POSITION int
   ) 
AS  
BEGIN 
	DECLARE @count int
	SET @count= 1

   IF(RIGHT(@string,1) = @delimitador)
      SET @string = LEFT(@string, LEN(@string)-1)

	WHILE (CHARINDEX(@delimitador,@string)>0)
	BEGIN
		INSERT INTO @array (VALUE, POSITION)
		SELECT LTRIM(RTRIM(SUBSTRING(@string,1,CHARINDEX(@delimitador,@string)-1))), @count

		SET @string = SUBSTRING(@string,CHARINDEX(@delimitador,@string)+1,LEN(@string))
		SET @count += 1
	END
	
	INSERT INTO @array (VALUE, POSITION)
	SELECT LTRIM(RTRIM(@string)), @count

	RETURN
END