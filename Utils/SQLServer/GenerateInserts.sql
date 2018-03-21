-- =====================================================================
-- Author: Fernando Prass | Create date: 03/11/2014
-- Language: T-SQL for SQL Server 2010+
-- Description: Generate INSERTs command from a table records
-- Contact: https://gitlab.com/fernando.prass or https://twitter.com/oFernandoPrass
-- Parameters
--    @owner -> table schema
--    @table_name -> table name
--    @where -> SQL WHERE clause
--    @orderBy -> set [A] for Ascending (default) or [D] for Descending in SQL ORDER BY clause
--    @numberOfRecords -> mumber of records
--    @include_column_list -> set [1] to show the name of the columns or [0] to hide
--    @cols_to_include -> Choose the columns that will be displayed
--    @cols_to_exclude -> Choose the columns that will be excluded
-- =====================================================================
alter PROCEDURE [spGenerateInserts]
   ( @owner varchar(50)
    , @table_name varchar(200)
    , @where varchar(200) = NULL
    , @orderBy char(1) = 'A'
    , @numberOfRecords int = NULL
    , @include_column_list bit = 0
    , @cols_to_include varchar(4000) = NULL
    , @cols_to_exclude varchar(4000) = NULL
   )
AS
BEGIN
   SET NOCOUNT ON

   DECLARE
      @disable_constraints bit = 0,         -- Quando 1, desativa restrições de chaves estrangeiras e permite-lhes após o INSERT
      @ommit_computed_cols bit = 1,         -- Quando 1, colunas computadas não serão incluídas na declaração INSERT
      @ommit_images bit = 0,                -- Utilize este parâmetro para gerar instruções INSERT, omitindo as colunas de 'imagem'
      @include_timestamp bit = 1,           -- Especifique 1 para este parâmetro, se você deseja incluir os dados TIMESTAMP / coluna rowversion na instrução INSERT
      @debug_mode bit = 0,                  -- Se debug_mode @ é definida como 1, os comandos SQL construídos por esse procedimento será impresso para posterior exame
      @from varchar(800) = NULL,            -- Utilize este parâmetro para filtrar as linhas com base em uma condição de filtro (usando WHERE)
      @ommit_identity bit,                  -- Utilize este parâmetro para omitir as colunas de identidade , por default omite esse tipo de coluna no insert
      @target_table varchar(776) = NULL     -- Utilize este parâmetro para especificar um nome de tabela diferente na qual os dados serão inseridos

   --verifica se a coluna é IDENTITY (se for não insere no insert)
   SELECT @ommit_identity = c.is_identity
   FROM SYS.ALL_COLUMNS c
      INNER JOIN SYS.TABLES t ON t.OBJECT_ID = c.OBJECT_ID
      INNER JOIN SYS.SCHEMAS s ON s.SCHEMA_ID = t.SCHEMA_ID
   WHERE s.NAME = @owner
      AND t.NAME = @table_name
      AND c.NAME = 'ID_' + @table_name

   IF(@where IS NOT NULL AND PATINDEX('WHERE%',@where) = 0)
      SET @where = 'WHERE ' + @where

   --Making sure user only uses either @cols_to_include or @cols_to_exclude
   IF ((@cols_to_include IS NOT NULL) AND (@cols_to_exclude IS NOT NULL))
   BEGIN
       RAISERROR('Use @cols_to_include ou @cols_to_exclude. Não usar os parâmetros de uma só vez',16,1)
       RETURN -1
   END

   --Making sure the @cols_to_include and @cols_to_exclude parameters are receiving values in proper format
   IF ((@cols_to_include IS NOT NULL) AND (PATINDEX('''%''',@cols_to_include) = 0))
   BEGIN
       RAISERROR('Uso inválido de propriedade @cols_to_include',16,1)
       PRINT 'Especifique os nomes de coluna entre aspas simples e separados por vírgulas'
       RETURN -1
   END

   IF ((@cols_to_exclude IS NOT NULL) AND (PATINDEX('''%''',@cols_to_exclude) = 0))
   BEGIN
       RAISERROR('Uso inválido de propriedade @cols_to_exclude',16,1)
       PRINT 'Especifique os nomes de coluna entre aspas simples e separados por vírgulas'
       RETURN -1
   END

   --Variable declarations
   DECLARE @Column_ID int, @Column_List varchar(8000), @Column_Name varchar(128), @Start_Insert varchar(786), @Data_Type varchar(128),
           @Actual_Values varchar(8000),    @IDN varchar(128)   

   --Variable Initialization
   SET @IDN = ''
   SET @Column_ID = 0
   SET @Column_Name = ''
   SET @Column_List = ''
   SET @Actual_Values = ''

   SET @Start_Insert = 'INSERT INTO ' + '[' + LTRIM(RTRIM(@owner)) + '].' + '[' + RTRIM(COALESCE(@target_table,@table_name)) + ']'        

   SELECT @Column_ID = MIN(ORDINAL_POSITION)    
   FROM INFORMATION_SCHEMA.COLUMNS (NOLOCK)
   WHERE TABLE_NAME = @table_name
      AND TABLE_SCHEMA = @owner

   --Loop through all the columns of the table, to get the column names and their data types
   WHILE @Column_ID IS NOT NULL
   BEGIN
       SELECT @Column_Name = QUOTENAME(COLUMN_NAME)
          , @Data_Type = DATA_TYPE
       FROM INFORMATION_SCHEMA.COLUMNS (NOLOCK)
       WHERE ORDINAL_POSITION = @Column_ID
          AND TABLE_NAME = @table_name
          AND TABLE_SCHEMA = @owner

      IF @cols_to_include IS NOT NULL --Selecting only user specified columns
           IF CHARINDEX( '''' + SUBSTRING(@Column_Name,2,LEN(@Column_Name)-2) + '''',@cols_to_include) = 0
               GOTO SKIP_LOOP

       IF @cols_to_exclude IS NOT NULL --Selecting only user specified columns
           IF CHARINDEX( '''' + SUBSTRING(@Column_Name,2,LEN(@Column_Name)-2) + '''',@cols_to_exclude) <> 0
               GOTO SKIP_LOOP

       --Making sure to output SET IDENTITY_INSERT ON/OFF in case the table has an IDENTITY column
       IF (SELECT COLUMNPROPERTY( OBJECT_ID(QUOTENAME(COALESCE(@owner,USER_NAME())) + '.' + @table_name),SUBSTRING(@Column_Name,2,LEN(@Column_Name) - 2),'IsIdentity')) = 1
       BEGIN
           IF @ommit_identity = 0 --Determing whether to include or exclude the IDENTITY column
               SET @IDN = @Column_Name
           ELSE
               GOTO SKIP_LOOP           
       END
       
       --Making sure whether to output computed columns or not
       IF @ommit_computed_cols = 1
           IF (SELECT COLUMNPROPERTY( OBJECT_ID(QUOTENAME(COALESCE(@owner,USER_NAME())) + '.' + @table_name),SUBSTRING(@Column_Name,2,LEN(@Column_Name) - 2),'IsComputed')) = 1
               GOTO SKIP_LOOP                   
       
       --Tables with columns of IMAGE data type are not supported for obvious reasons
       IF(@Data_Type in ('image'))
       BEGIN
           IF (@ommit_images = 0)
           BEGIN
               RAISERROR('As tabelas com colunas de imagem não são suportadas.',16,1)
               PRINT 'Use @ommit_images = 1 parâmetro para gerar inserções para o resto das colunas.'
               RETURN -1
           END
           ELSE
              GOTO SKIP_LOOP
       END

       --Determinar o tipo de dados da coluna e, dependendo do tipo de dados, a parte VALUES da instrução INSERT é gerado.
       --O cuidado é tomado para lidar com colunas com valores NULL.
       --Também certificando-se, para não perder nenhum dados de flot, real, smallmomey, colunas datetime
       SET @Actual_Values = @Actual_Values 
                          + CASE WHEN @Data_Type IN ('char','varchar','nchar','nvarchar') THEN 'COALESCE('''''''' + REPLACE(RTRIM(' + @Column_Name + '),'''''''','''''''''''')+'''''''',''NULL'')'
                                  WHEN @Data_Type IN ('datetime','smalldatetime','time','date') THEN 'COALESCE('''''''' + CONVERT(varchar,' + @Column_Name + ',21)+'''''''',''NULL'')'
                                  WHEN @Data_Type IN ('uniqueidentifier') THEN 'COALESCE('''''''' + REPLACE(CONVERT(varchar(255),RTRIM(' + @Column_Name + ')),'''''''','''''''''''')+'''''''',''NULL'')'
                                  WHEN @Data_Type IN ('text','ntext') THEN 'COALESCE('''''''' + REPLACE(CONVERT(varchar(8000),' + @Column_Name + '),'''''''','''''''''''')+'''''''',''NULL'')'                   
                                  WHEN @Data_Type IN ('binary','varbinary') THEN 'COALESCE(RTRIM(CONVERT(char,' + 'CONVERT(int,' + @Column_Name + '))),''NULL'')' 
                                  WHEN @Data_Type IN ('timestamp','rowversion') THEN  CASE WHEN @include_timestamp = 0 THEN '''DEFAULT''' ELSE 'COALESCE(RTRIM(CONVERT(char,' + 'CONVERT(int,' + @Column_Name + '))),''NULL'')'  END
                                  WHEN @Data_Type IN ('float','real','money', 'numeric','smallmoney') THEN 'COALESCE(LTRIM(RTRIM(' + 'CONVERT(char, ' +  @Column_Name  + ',2)' + ')),''NULL'')'
                              ELSE 'COALESCE(LTRIM(RTRIM(' + 'CONVERT(char, ' +  @Column_Name  + ')' + ')),''NULL'')'
                             END   + '+' +  ''',''' + ' + '
                               
       -- Geração da lista de colunas para a instrução INSERT
       SET @Column_List = @Column_List +  @Column_Name + ','   

       SKIP_LOOP: --variavel para ser utilizada pelo GOTO

       SELECT @Column_ID = MIN(ORDINAL_POSITION)
       FROM INFORMATION_SCHEMA.COLUMNS (NOLOCK)
       WHERE TABLE_NAME = @table_name
          AND ORDINAL_POSITION > @Column_ID
          AND TABLE_SCHEMA = @owner

   --Loop finaliza aqui
   END

   -- Para se livrar dos personagens extras que tenho concatenados durante a última corrida através do laço
   SET @Column_List = LEFT(@Column_List,len(@Column_List) - 1)
   SET @Actual_Values = LEFT(@Actual_Values,len(@Actual_Values) - 6)

   IF LTRIM(@Column_List) = ''
   BEGIN
       RAISERROR('Não há colunas para selecionar. Não deveria ser pelo menos uma coluna para gerar a saída',16,1)
       RETURN -1
   END

   -- Formar a seqüência final, que será executado, a saída do comando INSERT
   IF (@include_column_list <> 0)
   BEGIN
       SET @Actual_Values = 'SELECT '
                          + CASE WHEN @numberOfRecords IS NULL OR @numberOfRecords < 0 THEN '' ELSE ' TOP ' + LTRIM(STR(@numberOfRecords)) + ' ' END
                          + '''' + RTRIM(@Start_Insert)
                          + ' ''+' + '''(' + RTRIM(@Column_List) +  '''+' + ''')'''
                          + ' +''VALUES(''+ ' +  LTRIM(RTRIM(@Actual_Values)) + '+'')''' + ' '
                          + COALESCE(@from,' FROM ' + CASE WHEN @owner IS NULL THEN '' ELSE '[' + LTRIM(RTRIM(@owner)) + '].' END + '[' + rtrim(@table_name) + ']' + '(NOLOCK) ')
                          + COALESCE(@where,'')
                          + 'ORDER BY ' + CASE WHEN @ommit_identity = 1 THEN 'ID_' + @table_name ELSE '1' END + CASE WHEN @orderBy = 'D' THEN ' DESC' ELSE ' ASC' END
   END
   ELSE IF (@include_column_list = 0)
   BEGIN
       SET @Actual_Values = 'SELECT '
                          + CASE WHEN @numberOfRecords IS NULL OR @numberOfRecords < 0 THEN '' ELSE ' TOP ' + LTRIM(STR(@numberOfRecords)) + ' ' END
                          + '''' + RTRIM(@Start_Insert)
                          + ' '' +''VALUES(''+ ' +  LTRIM(RTRIM(@Actual_Values)) + '+'')''' + ' '
                          + COALESCE(@from,' FROM ' + CASE WHEN @owner IS NULL THEN '' ELSE '[' + LTRIM(RTRIM(@owner)) + '].' END + '[' + rtrim(@table_name) + ']' + '(NOLOCK)')
                          + COALESCE(@where,'')
                          + 'ORDER BY ' + CASE WHEN @ommit_identity = 1 THEN 'ID_' + @table_name ELSE '1' END + CASE WHEN @orderBy = 'D' THEN ' DESC' ELSE ' ASC' END
   END   

   --Determining whether to ouput any debug information
   IF @debug_mode =1
   BEGIN
       PRINT '/*****START OF DEBUG INFORMATION*****'
       PRINT 'Beginning of the INSERT statement:'
       PRINT @Start_Insert
       PRINT ''
       PRINT 'The column list:'
       PRINT @Column_List
       PRINT ''
       PRINT 'The SELECT statement executed to generate the INSERTs'
       PRINT @Actual_Values
       PRINT ''
       PRINT '*****END OF DEBUG INFORMATION*****/'
       PRINT ''
   END

   --Determining whether to print IDENTITY_INSERT or not
   IF (@IDN <> '')
   BEGIN
       PRINT 'SET IDENTITY_INSERT ' + QUOTENAME(COALESCE(@owner,USER_NAME())) + '.' + QUOTENAME(@table_name) + ' ON'
       PRINT 'GO'
       PRINT ''
   END

   IF @disable_constraints = 1 AND (OBJECT_ID(QUOTENAME(COALESCE(@owner,USER_NAME())) + '.' + @table_name, 'U') IS NOT NULL)
   BEGIN
       IF @owner IS NULL
       BEGIN
           SELECT 'ALTER TABLE ' + QUOTENAME(COALESCE(@target_table, @table_name)) + ' NOCHECK CONSTRAINT ALL' AS '--Code to disable constraints temporarily'
       END
       ELSE
       BEGIN
           SELECT 'ALTER TABLE ' + QUOTENAME(@owner) + '.' + QUOTENAME(COALESCE(@target_table, @table_name)) + ' NOCHECK CONSTRAINT ALL' AS '--Code to disable constraints temporarily'
       END

       PRINT 'GO'
   END

   PRINT ''
   PRINT 'PRINT ''Inserindo valores em ' + '[' + RTRIM(COALESCE(@target_table,@table_name)) + ']' + ''''


   --All the hard work pays off here!!! You'll get your INSERT statements, when the next line executes!
   EXEC (@Actual_Values)

   PRINT 'PRINT ''Done'''
   PRINT ''

   IF @disable_constraints = 1 AND (OBJECT_ID(QUOTENAME(COALESCE(@owner,USER_NAME())) + '.' + @table_name, 'U') IS NOT NULL)
   BEGIN
       IF @owner IS NULL
       BEGIN
           SELECT 'ALTER TABLE ' + QUOTENAME(COALESCE(@target_table, @table_name)) + ' CHECK CONSTRAINT ALL'  AS '--Code to enable the previously disabled constraints'
       END
       ELSE
       BEGIN
           SELECT 'ALTER TABLE ' + QUOTENAME(@owner) + '.' + QUOTENAME(COALESCE(@target_table, @table_name)) + ' CHECK CONSTRAINT ALL' AS '--Code to enable the previously disabled constraints'
       END

       PRINT 'GO'
   END

   PRINT ''
   IF (@IDN <> '')
   BEGIN
       PRINT 'SET IDENTITY_INSERT ' + QUOTENAME(COALESCE(@owner,USER_NAME())) + '.' + QUOTENAME(@table_name) + ' OFF'
       PRINT 'GO'
   END

   SET NOCOUNT OFF
  
   RETURN 0
END