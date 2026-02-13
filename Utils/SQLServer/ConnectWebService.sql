-- =====================================================================
-- Author: Fernando Prass | Create date: 03/11/2016
-- Language: T-SQL for SQL Server 2010+
-- Description: Connect a Web Service and get a Brazilian address informing the CEP (ZIP code)
-- Note: You must activate OLE automation procedures to use this
-- Contact: https://github.com/fernandoprass or https://twitter.com/oFernandoPrass
-- =====================================================================
CREATE PROCEDURE [spGetAddressByCEP] (
    @nrCep VARCHAR(20)
)
AS BEGIN
     DECLARE @obj INT, @Url VARCHAR(255), @resposta VARCHAR(8000), @xml XML
  
    -- Recupera apenas os n�meros do CEP
    DECLARE @startingIndex INT = 0
    
    WHILE (1=1)
    BEGIN
        SET @startingIndex = PATINDEX('%[^0-9]%', @nrCep)  
        IF (@startingIndex <> 0)
            SET @nrCep = REPLACE(@nrCep, SUBSTRING(@nrCep, @startingIndex, 1), '')  
        ELSE    
            BREAK
    END
    
    SET @Url = 'http://viacep.com.br/ws/' + @nrCep + '/xml'
 
    EXEC sys.sp_OACreate 'MSXML2.ServerXMLHTTP', @obj OUT
    EXEC sys.sp_OAMethod @obj, 'open', NULL, 'GET', @Url, FALSE
    EXEC sys.sp_OAMethod @obj, 'send'
    EXEC sys.sp_OAGetProperty @obj, 'responseText', @resposta OUT
    EXEC sys.sp_OADestroy @obj
    
    SET @xml = @resposta COLLATE SQL_Latin1_General_CP1251_CS_AS
    
    SELECT
        @xml.value('(/xmlcep/cep)[1]', 'varchar(9)') AS CEP,
        @xml.value('(/xmlcep/logradouro)[1]', 'varchar(200)') AS Street,
        @xml.value('(/xmlcep/complemento)[1]', 'varchar(200)') AS Complement,
        @xml.value('(/xmlcep/bairro)[1]', 'varchar(200)') AS Neighborhood,
        @xml.value('(/xmlcep/localidade)[1]', 'varchar(200)') AS City,
        @xml.value('(/xmlcep/uf)[1]', 'varchar(200)') AS State,
        @xml.value('(/xmlcep/ibge)[1]', 'varchar(200)') AS BrazilianCityCode
 
END