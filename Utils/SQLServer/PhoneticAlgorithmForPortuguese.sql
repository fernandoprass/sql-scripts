-- =====================================================================
-- Author: Fernando Prass | Create date: 03/11/2015
-- Language: T-SQL for SQL Server 2010+
-- Description: Phonetic algorithm for Portuguese Language
-- Note: There are six different functions here, you need to run one by one
-- Contact: https://gitlab.com/fernando.prass or https://twitter.com/oFernandoPrass
-- =====================================================================

CREATE FUNCTION [dbo].[fcPhonetic] (@VALUE VARCHAR(5000), @CONSULTA CHAR(1))
RETURNS VARCHAR(5000)
AS
BEGIN
DECLARE
  @PARTICULA        VARCHAR(5000),
  @FONETIZADO       VARCHAR(5000),
  @FONETIZAR        CHAR(1),
  @AUX              VARCHAR(5000),
  @I                INT,
  @CONT             INT,
  @PREPOSICOES1     VARCHAR(1000),
  @PREPOSICOES2     VARCHAR(1000),
  @ALGROMANO1       VARCHAR(1000),
  @NUMERO1          VARCHAR(1000),
  @ALGROMANO2       VARCHAR(1000),
  @NUMERO2          VARCHAR(1000),
  @ALGROMANO3       VARCHAR(1000),
  @NUMERO3          VARCHAR(1000),
  @ALGARISMO        VARCHAR(1000),
  @ALGARISMOEXTENSO VARCHAR(1000),
  @LETRAS           VARCHAR(1000)

  SELECT @VALUE = dbo.fcFonetizarRemoveAcento(@VALUE)

  /*********************************************/
  IF @VALUE = ' H '
     SET @VALUE = ' AGA '

  SELECT @VALUE = dbo.fcFonetizarSomenteLetras(@VALUE)

  /*ELIMINAR PALAVRAS ESPECIAIS*/
  SELECT @VALUE = REPLACE(@VALUE,' LTDA ',' ')

  /*ELIMINAR PREPOSICOES*/
  SET @PREPOSICOES1 = ' DE  DA  DO  AS  OS  AO  NA  NO '
  SET @PREPOSICOES2 = ' DOS  DAS  AOS  NAS  NOS  COM '

  SET @I = 1

  WHILE @I <= 32
  BEGIN
     SELECT @VALUE = REPLACE(@VALUE,SUBSTRING(@PREPOSICOES1,@I,4),' ')
     SET @I = @I + 4
  END

  SET @I = 1

  WHILE @I <= 30
  BEGIN
     SELECT @VALUE = REPLACE(@VALUE,SUBSTRING(@PREPOSICOES2,@I,5),' ')
     SET @I = @I + 5
  END

  /*CONVERTE ALGARISMO ROMANO PARA NUMERO*/
  SET @ALGROMANO1 = ' V  I '
  SET @NUMERO1    = ' 5  1 '
  SET @I = 1
  WHILE @I <= 6
  BEGIN
     SELECT @VALUE = REPLACE(@VALUE,SUBSTRING(@ALGROMANO1,@I,3),SUBSTRING(@NUMERO1,@I,3))
     SET @I = @I + 3
  END

  SET @ALGROMANO2 = ' IX  VI  IV  II '
  SET @NUMERO2    = '  9   6   4   2 '
  SET @I = 1
  WHILE @I <= 16
  BEGIN
     SELECT @VALUE = REPLACE(@VALUE,SUBSTRING(@ALGROMANO2,@I,4),SUBSTRING(@NUMERO2,@I+1,3))
     SET @I = @I + 4
  END

  SET @ALGROMANO3 = ' VII  III '
  SET @NUMERO3    = '   7    3 '
  SET @I = 1
  WHILE @I <= 10
  BEGIN
     SELECT @VALUE = REPLACE(@VALUE,SUBSTRING(@ALGROMANO3,@I,5),SUBSTRING(@NUMERO3,@I+2,3))
     SET @I = @I + 5
  END

  SELECT @VALUE = REPLACE(@VALUE,' X ',' 10 ')
  SELECT @VALUE = REPLACE(@VALUE,' VIII ',' 8 ')


  /*CONVERTE NUMERO PARA LITERAL*/
  SELECT @VALUE = REPLACE(@VALUE,'0','ZERO')
  SELECT @VALUE = REPLACE(@VALUE,'1','UM')
  SELECT @VALUE = REPLACE(@VALUE,'2','DOIS')
  SELECT @VALUE = REPLACE(@VALUE,'3','TRES')
  SELECT @VALUE = REPLACE(@VALUE,'4','QUATRO')
  SELECT @VALUE = REPLACE(@VALUE,'5','CINCO')
  SELECT @VALUE = REPLACE(@VALUE,'6','SEIS')
  SELECT @VALUE = REPLACE(@VALUE,'7','SETE')
  SELECT @VALUE = REPLACE(@VALUE,'8','OITO')
  SELECT @VALUE = REPLACE(@VALUE,'9','NOVE')


  /*********************************************/
  /*ELIMINAR PREPOSICOES E ARTIGOS*/
  SET @LETRAS = ' A  B  C  D  E  F  G  H  I  J  K  L  M  N  O  P  Q  R  S  T  U  V  X  Z  W  Y ';

  SET @I = 1
  WHILE @I <= 78
  BEGIN
     SELECT @VALUE = REPLACE(@VALUE,SUBSTRING(@ALGROMANO2,@I,3),' ')
     SET @I = @I + 3
  END


  SET @VALUE = LTRIM(@VALUE)
  SET @VALUE = RTRIM(@VALUE)

  SET @PARTICULA  = ''
  SET @FONETIZADO = ''

  SET @CONT = 1

  WHILE @CONT <= LEN(@VALUE)+1
  BEGIN
     IF @CONT < LEN(@VALUE) + 1
     BEGIN
        IF SUBSTRING(@VALUE,@CONT,1) <> ' '
        BEGIN
           SET @PARTICULA = @PARTICULA + SUBSTRING(@VALUE,@CONT,1)
           SET @FONETIZAR = '0'
        END
        ELSE
           SET @FONETIZAR = '1'
     END
     ELSE
        SET @FONETIZAR = '1'
     IF @FONETIZAR = '1'
     BEGIN
        SELECT @PARTICULA = dbo.fcFonetizarParticula(@PARTICULA)
        SET @FONETIZADO = @FONETIZADO + ' ' + @PARTICULA
        SET @PARTICULA = ''
     END
     SET @CONT = @CONT + 1
  END

  SET @FONETIZADO = LTRIM(@FONETIZADO)
  SET @FONETIZADO = RTRIM(@FONETIZADO)


  /*PREPARA A STRING PARA UM LIKE*/
  IF @CONSULTA = '1'
  BEGIN
    SET @AUX = '%'

    SET @I = 1

    WHILE @I <= LEN(@FONETIZADO)
    BEGIN
       IF SUBSTRING(@FONETIZADO,@I,1) = ' '
         SET @AUX = @AUX + '% %'
       ELSE
         SET @AUX = @AUX + SUBSTRING(@FONETIZADO,@I,1)
       SET @I = @I + 1
    END

    IF SUBSTRING(@FONETIZADO,LEN(@FONETIZADO),1) <> '%'
       SET @AUX = @AUX + '%'

    SET @FONETIZADO = @AUX
  END
  IF @FONETIZADO = ''
     SET @FONETIZADO = NULL
  
  RETURN @FONETIZADO
  
END



CREATE FUNCTION [dbo].[fcFonetizarParticula](@STR VARCHAR(5000))
RETURNS VARCHAR(5000)
AS
BEGIN
   DECLARE
      @AUX           VARCHAR(5000),
      @AUX2          VARCHAR(5000),
      @I             INT,
      @N             INT,
      @J             INT,
      @LETRAS        VARCHAR(26),
      @CODFONETICO   VARCHAR(26),
      @CARACTERES    VARCHAR(1000),
      @CARACTERESSUB VARCHAR(1000)

  /*CRIA A CODIFICAÇÃO DOS FONEMAS*/
   SET @LETRAS      = 'ABPCKQDTEIYFVWGJLMNOURSZX9'
   SET @CODFONETICO = '123444568880AABCDEEGAIJJL9'

  /*ELIMINA LETRAS IGUAIS SEGUIDAS UMA DA OUTRA*/

   SET @AUX = SUBSTRING(@STR,1,1) /*RECEBE A PRIMEIRA LETRA*/
   SET @I = 2
   
   WHILE @I <= LEN(@STR)
   BEGIN
      IF SUBSTRING(@STR,@I - 1,1) <> SUBSTRING(@STR,@I,1) 
         SET @AUX = @AUX + SUBSTRING(@STR,@I,1)
      SET @I = @I + 1
   END

  /*IGUALA FONEMAS PARECIDOS*/


  IF SUBSTRING(@AUX,1,1) = 'W'
     IF SUBSTRING(@AUX,2,1) = 'I'
        SET @AUX = 'U' + SUBSTRING(@AUX,2,LEN(@AUX)) /*TROCA W POR U*/
     ELSE
        IF SUBSTRING(@AUX,2,1) IN ('A','E','O','U')
           SET @AUX = 'V' + SUBSTRING(@AUX,2,LEN(@AUX)) /*TROCA W POR V*/
           


  SELECT @AUX = dbo.fcFonetizarSubstituiTerminacao(@AUX)

  SET @CARACTERES    = 'TSCHSCH TSH TCH SH  CH  LH  NH  PH  GN  MN  SCE SCI SCY CS  KS  PS  TS  TZ  XS  CE  CI  CY  GE  GI  GY  GD  CK  PC  QU  SC  SK  XC  SQ  CT  GT  PT  '
  SET @CARACTERESSUB = 'XXXXXXX XXX XXX XX  XX  LI  NN  FF  NN  NN  SSI SSI SSI SS  SS  SS  SS  SS  SS  SE  SI  SI  JE  JI  JI  DD  QQ  QQ  QQ  SQ  SQ  SQ  99  TT  TT  TT  '

  SET @I = 1
  WHILE @I <= 148
  BEGIN
     SELECT @AUX = REPLACE(@AUX,LTRIM(RTRIM(SUBSTRING(@CARACTERES,@I,4))), LTRIM(RTRIM(SUBSTRING(@CARACTERESSUB,@I,4))))
     SET @I = @I + 4
  END

  /*TRATAR CONSOANTES MUDAS*/
  SELECT @AUX = dbo.fcFonetizarTrataConsoanteMuda(@AUX,'B','I')
  SELECT @AUX = dbo.fcFonetizarTrataConsoanteMuda(@AUX,'D','I')
  SELECT @AUX = dbo.fcFonetizarTrataConsoanteMuda(@AUX,'P','I')

  -- TRATA LETRAS
  -- RETIRA LETRAS IGUAIS
  IF SUBSTRING(@AUX,1,1) = 'H'
  BEGIN
     SET @AUX2 = SUBSTRING(@AUX,2,1) -- RECEBE A SEGUNDA LETRA
     SET @J = 3
  END
  ELSE
  BEGIN
     SET @AUX2 = SUBSTRING(@AUX,1,1) -- RECEBE A PRIMEIRA LETRA
     SET @J = 2
  END

  WHILE @J <= LEN(@AUX)
  BEGIN
     IF (((SUBSTRING(@AUX,@J - 1,1) <> SUBSTRING(@AUX,@J,1))) AND
        (SUBSTRING(@AUX,@J,1) <> 'H'))
        SET @AUX2 = @AUX2 + SUBSTRING(@AUX,@J,1)
     SET @J = @J + 1
  END

  SET @AUX = @AUX2

  -- TRANSFORMA LETRAS EM CODIGOS FONETICOS
  SET @AUX2 = ''

  SET @I = 1

  WHILE @I <= LEN(@AUX)
  BEGIN
     SET @N = 1
     WHILE @N <= 26
     BEGIN
        IF SUBSTRING(@AUX,@I,1) = SUBSTRING(@LETRAS,@N,1)
           SET @AUX2 = @AUX2 + SUBSTRING(@CODFONETICO,@N,1)
        SET @N = @N + 1
     END
     SET @I = @I + 1
  END

  RETURN @AUX2
END

CREATE FUNCTION [dbo].[fcFonetizarRemoveAcento]( @TEXTO VARCHAR (5000))
RETURNS VARCHAR (5000)
AS
BEGIN
	DECLARE @COMACENTOS VARCHAR(50)
	DECLARE @SEMACENTOS VARCHAR(50)
	DECLARE @QTD_TEXTO INT
	DECLARE @CONTADOR INT
	DECLARE @QTD INT
	DECLARE @CONT INT
	DECLARE @CONT_C INT
	DECLARE @LETRA_T NVARCHAR(1)
	DECLARE @LETRA_C NVARCHAR(1)
	DECLARE @RESULTADO VARCHAR(5000)

	SET @COMACENTOS = 'áÁàÀâÂãÃéÉèÈêÊíÍìÌîÎóÓòÒôÔõÕúÚùÙûÛüÜçÇ'
	SET @SEMACENTOS = 'AAAAAAAAEEEEEEIIIIIIOOOOOOOOUUUUUUUUCC'
	SET @QTD_TEXTO  = (SELECT LEN(@TEXTO))
	SET @CONTADOR   = 0
	SET @RESULTADO  = ''

	INICIO:
	WHILE @CONTADOR < @QTD_TEXTO
	BEGIN
	  SET @CONTADOR = @CONTADOR + 1
	  SET @LETRA_T = (SELECT SUBSTRING(@TEXTO,@CONTADOR,1))
	  SET @CONT = (SELECT LEN(@COMACENTOS))
	  SET @QTD = 0
	  WHILE @QTD < @CONT
	  BEGIN
		  SET @QTD = @QTD + 1
		  SET @LETRA_C = (SELECT SUBSTRING(@COMACENTOS,@QTD,1))
		  IF @LETRA_C = @LETRA_T
		  BEGIN
			  SET @RESULTADO = @RESULTADO + (SELECT SUBSTRING(@SEMACENTOS,@QTD,1))
			  GOTO INICIO
		  END
		  ELSE
		  BEGIN
			  IF @QTD = @CONT
				  SET @RESULTADO =  @RESULTADO + @LETRA_T
		  END
	  END
	END

	RETURN ( UPPER(@RESULTADO) )
END

CREATE FUNCTION [dbo].[fcFonetizarSomenteLetras]( @TEXTO VARCHAR (5000))
RETURNS VARCHAR (5000)
AS
	BEGIN
	DECLARE @LETRAS    VARCHAR(28)
	DECLARE @QTD_TEXTO INT
	DECLARE @CONTADOR  INT
	DECLARE @QTD       INT
	DECLARE @CONT      INT
	DECLARE @CONT_C    INT
	DECLARE @LETRA_ANT NVARCHAR(1)
	DECLARE @LETRA_T   NVARCHAR(1)
	DECLARE @LETRA_C   NVARCHAR(1)
	DECLARE @RESULTADO VARCHAR(5000)


	SET @LETRAS = 'ABCDEFGHIJKLMNOPQRSTUVXZWY ';

	SET @QTD_TEXTO = (SELECT LEN(@TEXTO)) + 1
	SET @CONTADOR  = 0
	SET @RESULTADO = ''
	SET @LETRA_ANT = (SELECT SUBSTRING(@TEXTO,1,1))
	INICIO:
	WHILE @CONTADOR < @QTD_TEXTO
	BEGIN
	  SET @CONTADOR = @CONTADOR + 1
	  SET @LETRA_T = (SELECT SUBSTRING(@TEXTO,@CONTADOR,1))
	  SET @CONT = (SELECT LEN(@LETRAS)) + 1
	  SET @QTD = 0
	  WHILE @QTD < @CONT
	  BEGIN
		  SET @QTD = @QTD + 1
		  SET @LETRA_C = (SELECT SUBSTRING(@LETRAS,@QTD,1))
		  IF @LETRA_C = @LETRA_T
		  BEGIN
			  IF @LETRA_ANT = ' '
				  AND @LETRA_T = ' '
			  BEGIN
				  GOTO INICIO
			  END
			  ELSE
			  BEGIN
				  SET @RESULTADO = @RESULTADO + (SELECT SUBSTRING(@LETRAS,@QTD,1))
				  SET @LETRA_ANT = @LETRA_T
				  GOTO INICIO
			  END
		  END
	  END
	END

	RETURN ( UPPER(@RESULTADO) )

END

create FUNCTION [dbo].[fcFonetizarSubstituiTerminacao](@STR VARCHAR(5000))
RETURNS VARCHAR(5000)
AS
BEGIN
   DECLARE
      @TERMINACAO    VARCHAR(1000),
      @TERMINACAOSUB VARCHAR(1000),
      @TAMANHOMINSTR VARCHAR(1000),
      @I INT

/*
SUBSTITUI AS TERMINAÇÕES CONTIDAS NO VETOR $vTerminacao PELAS DO VETOR $vTerminacaoSub RESPEITANDO
O TAMANHO MÍNIMO DA STRING CONTIDO NO VETOR $vTamanhoMinStr.
NO CASO DA STRING TERMINAR COM 'N', O LAÇO CONTINUARÁ, POIS PODERÃO EXIXTIR NOVAS SUBSTITUIÇÕES COM
A TERMINAÇÃO 'M'.
*/
      SELECT @STR = dbo.fcFonetizarRemoveAcento(@STR)
      
      SET @TERMINACAO    = 'N  B  D  T  W  AM OM OIMUIMCAOAO OEMONSEIAX  US TH'
      SET @TERMINACAOSUB = 'M              N  N  N  N  SSNN  N  N  IA IS OS TI'
      SET @TAMANHOMINSTR = '2  3  3  3  3  2  2  2  2  3  2  2  2  2  2  2  3'
      SET @I             = 1

   LOOP:
   BEGIN
	
      IF RTRIM(SUBSTRING(@STR,LEN(@STR) - LEN(SUBSTRING(@TERMINACAO,@I,3)) + 1,LEN(SUBSTRING(@TERMINACAO,@I,3)))) = RTRIM(SUBSTRING(@TERMINACAO,@I,3)) AND
         (LEN(@STR) >= CONVERT(INT,SUBSTRING(@TAMANHOMINSTR,@I,3)))
      BEGIN
         SET @STR = SUBSTRING(@STR,1,LEN(@STR) - LEN(SUBSTRING(@TERMINACAO,@I,3))) + RTRIM(SUBSTRING(@TERMINACAOSUB,@I,3))
         IF @I > 1
            GOTO FIM
      END
    
      SET @I = @I + 3

	  IF @I < 52
	     GOTO LOOP

   END

   FIM:
   BEGIN	
      RETURN @STR
   END

END


create FUNCTION [dbo].[fcFonetizarTrataConsoanteMuda](@STR VARCHAR(5000), @CONSOANTE CHAR(1), @COMPLEMENTO CHAR(1))
RETURNS VARCHAR(5000)
AS
BEGIN
   DECLARE
     @I INT,
     @CONTADOR INT

	/*
	PARA TODAS AS OCORRÊNCIAS DA CONSOANTE $consoante QUE NÃO ESTIVER SEGUIDA DE VOGAL, SERÁ ADICIONADO
	O CONTEÚDO DA VARIÁVEL $complemento NA STRING.
	*/

   SET @I = LEN(@STR)
   SET @CONTADOR = 1

   LOOP:
   BEGIN

--  for i in 1..length(tStr) loop
      IF ((SUBSTRING(@STR,@CONTADOR,1) = @CONSOANTE) AND
          (SUBSTRING(@STR,@CONTADOR + 1,1) NOT IN ('A','E','I','O','U')))

          SET @STR = SUBSTRING(@STR,1,@CONTADOR) + @COMPLEMENTO + SUBSTRING(@STR,@CONTADOR + 1,LEN(@STR))

      SET @CONTADOR = @CONTADOR + 1

      IF @CONTADOR <= @I
         GOTO LOOP

    END  		

    RETURN @STR

END

