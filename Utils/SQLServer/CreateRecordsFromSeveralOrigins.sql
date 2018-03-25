-- =====================================================================
-- Author: Fernando Prass | Create date: 23/06/2016
-- Language: T-SQL for SQL Server 2010+
-- Description: This code is part of an Accounting software, it generate records from several origins.
--              With it, you can configure what Accounting entries need be generate when one events happens 
--              (eg.: when the company pays an account you need to register the debit and the withdrawal into the bank account
-- Contact: https://gitlab.com/fernando.prass or https://twitter.com/oFernandoPrass
-- =====================================================================

ALTER PROCEDURE [dbo].[spGerarLancamentos]
    ( @nomeTabela varchar(50)
    , @idTabela integer
    , @idUsuario integer
    , @BeneficiarioCheque char(1)
    , @idPessoaBordero integer
    , @retorno int OUTPUT
    )
AS

DECLARE @sqlOrigemPagamento nvarchar(2000), @idTciOrigemPagamento int, @parametro nvarchar(100), @lIdPessoa int, @lNomePessoa varchar(300)
      , @dataHoraLancamento datetime, @idTciFormaPagamento int, @dataHoraLancamentoTabela datetime, @cont int, @idPessoaBeneficiario integer
      , @mes varchar(2), @ano varchar(4), @idProjetoMeta integer, @sqlMeta nvarchar(2000), @contaAtiva char(1), @idProjetoMetaLancamento int
      , @saldoContaContabil numeric(18,2), @validarLancamento char(1), @classificador1 char(1), @tipoProjeto char(1), @valorSaldoProjeto numeric(18,2)
      , @permiteLancamento char(1), @cpfCnpj varchar(20), @projetoPendente char(1), @idPessoaFuncionario integer
      , @codigoContabil varchar(6), @contaCorrenteRubrica varchar(20), @contaCorrenteProjeto varchar(20), @idFundacao integer, @vincularProjeto char(1)
      , @estrangeiro char(1), @geraPagamento char(1), @idTciOrigemLancamento int, @pisPasep varchar(20), @validarLancamentoTrf char(1)
      , @idCentralDespesa int, @ret int, @siconv char(1), @idTciOrigemLancamentoLivre int, @dataAgendamento varchar(10), @GerarDocPagamento char(1)
      , @permiteDataDocPosterior char(1), @usarDataSistemaParaLancamento char(1), @liberarPgtoPessoa char(1)

SET @mes = REPLICATE('0',2-LEN(DATEPART(MONTH,GETDATE()))) + CONVERT(varchar(2),DATEPART(MONTH,GETDATE()))
SET @ano = REPLICATE('0',4-LEN(DATEPART(YEAR,GETDATE()))) + CONVERT(varchar(4),DATEPART(YEAR,GETDATE()))
SET @retorno = 0
SET @dataHoraLancamento = GETDATE()
SET @cont = 0
SET @validarLancamentoTrf = 'S' --por default valida os saldo dos lançamento da TRF
SELECT @idTciOrigemLancamentoLivre = dbo.fcBuscarTabelaCampoItemPorNome('LANCAMENTO', 'ORIGEM_LANCAMENTO', 'LANCAMENTO LIVRE')
SELECT @permiteDataDocPosterior = dbo.fcBuscarValorParametro('LANCAMENTO', 'PERMITE_LANCAMENTO_DATA_DOC_POSTERIOR')
SELECT @usarDataSistemaParaLancamento = dbo.fcBuscarValorParametro('LANCAMENTO', 'DATA_LANCAMENTO_USAR_DATA_SISTEMA')

IF(@nomeTabela = 'TRF')
BEGIN
   --se for lancamento para o mesmo projeto da TRF, não valida pois "provavelmente" seja uma TRF para ajuste de saldo das metas
   SELECT @validarLancamentoTrf = CASE WHEN COUNT(*) > 0 THEN 'N' ELSE 'S' END
   FROM TRF
   WHERE ID_TRF = @idTabela
      AND ID_PROJETO_ORIGEM = ID_PROJETO_DESTINO
END

--verifica se existe o registro na tabela LANCAMENTO_MES fechado (não permitindo lançamentos)
EXEC dbo.spLancamentoMes @dataHoraLancamento, @retorno OUTPUT
IF(ISNULL(@retorno,0) > 0)
   RETURN

SELECT @nomeTabela = dbo.fcRetiraQuebraDeLinha (@nomeTabela)

SELECT @sqlOrigemPagamento = 'SELECT @retorno1 = ID_TCI_ORIGEM_PAGAMENTO '
                                 + ' , @retorno2 = ID_TCI_FORMA_PAGAMENTO '
                                 + ' , @retorno3 = DATA_HORA_LANCAMENTO '
                           + 'FROM dbo.' + @nomeTabela
                           + ' WHERE ID_' + @nomeTabela + ' = @id '
SET @parametro = N'@id int, @retorno1 int OUTPUT, @retorno2 int OUTPUT, @retorno3 datetime OUTPUT'
EXECUTE sp_executesql  @sqlOrigemPagamento
                     , @parametro
                     , @id = @idTabela
                     , @retorno1=@idTciOrigemPagamento OUTPUT
                     , @retorno2=@idTciFormaPagamento OUTPUT
                     , @retorno3=@dataHoraLancamentoTabela OUTPUT

IF(@dataHoraLancamentoTabela IS NOT NULL AND @nomeTabela <> 'ADIANTAMENTO' AND @nomeTabela <> 'LANCAMENTO_ESTORNO')
   SET @retorno = 3 --Já foram gerados os lançamentos para este item
ELSE IF(@idTciOrigemPagamento IS NULL)
   SET @retorno = 6 --O campo Origem do Pagamento é de preenchimento obrigatório
ELSE IF(@idTciFormaPagamento IS NULL)
   SET @retorno = 7 --O campo Forma de Pagamento é de preenchimento obrigatório
ELSE IF((SELECT ISNULL(PERMITE_LANCAR,'N') FROM USUARIO WHERE ID_USUARIO = @idUsuario) = 'N')
   SET @retorno = 40 --Você não tem permissão para realizar essa operação. Consulte o Administrador do Sistema.

IF(@retorno > 0)
   RETURN
 
BEGIN TRY
   SELECT @sqlMeta = 'SELECT @projetoMeta = ID_PROJETO_META '
                   + 'FROM dbo.' + @nomeTabela
                   + ' WHERE ID_' + @nomeTabela + ' = @id '
   SET @parametro = N'@id int, @projetoMeta int OUTPUT'
   EXECUTE sp_executesql  @sqlMeta
                        , @parametro
                        , @id = @idTabela
                        , @projetoMeta=@idProjetoMeta OUTPUT
   IF(@idProjetoMeta IS NULL)
      SET @idProjetoMeta = -1 --seta como -1 pois o usuario pode não ter selecionado a meta para fazer o rateio
END TRY
BEGIN CATCH
   SET @idProjetoMeta = NULL
END CATCH

BEGIN TRY
   SELECT @sqlMeta = 'SELECT @CentralDespesa = cd.ID_CENTRAL_DESPESA '
                   + 'FROM ' + @nomeTabela + ' as t '
                   + '  INNER JOIN dbo.CENTRAL_DESPESA cd ON cd.ID_CENTRAL_DESPESA = t.ID_CENTRAL_DESPESA '
                   + 'WHERE cd.DATA_HORA_FECHAMENTO IS NOT NULL '
                   + '  AND t.ID_' + @nomeTabela + ' = @id '
   SET @parametro = N'@id int, @CentralDespesa int OUTPUT'
   EXECUTE sp_executesql  @sqlMeta
                        , @parametro
                        , @id = @idTabela
                        , @CentralDespesa=@idCentralDespesa OUTPUT
END TRY
BEGIN CATCH
   SET @idCentralDespesa = NULL
END CATCH

--******************************************************************
--insere o registro na GUIA
--******************************************************************
SELECT TOP 1 @idTciOrigemLancamento = ID_TCI_ORIGEM
FROM dbo.LANCAMENTO_CONFIGURACAO
WHERE TABELA = @nomeTabela

--IF(@idTciOrigemLancamento IS NOT NULL)
--   EXEC dbo.spGuiaInserir @idTciOrigemLancamento, @idTabela, @idUsuario
--******************************************************************
 
BEGIN TRANSACTION

DECLARE @id_lancamento_configuracao int, @tabela varchar(31), @tabelaProjeto varchar(31), @tipo char(1), @campo_doc_numero varchar(31)
      , @campo_doc_data varchar(31), @campo_doc_valor varchar(31), @condicao varchar(500), @origem_conta_contabil char(1)
      , @id_conta_contabil_occ int, @id_lancamento_tipo int, @id_tci_forma_pagamento int, @id_tci_origem_pagamento int
      , @id_tci_origem int, @id_lancamento int, @gera_bordero char(1), @gera_cheque char(1), @cheque_bordero_beneficiario char(1)
      , @complemento varchar(200), @nomeCampoProjeto varchar(30), @nomeCampoContaContabil varchar(50), @nomeCampoProjetoMeta varchar(30)
      , @tabela_lancamento_tipo varchar(31), @agendamento char(1), @dia smallint

DECLARE crLancamentoContabil CURSOR
    KEYSET FOR
      SELECT  ID_LANCAMENTO_CONFIGURACAO, TABELA, TABELA_PROJETO, TIPO, CAMPO_DOC_NUMERO, CAMPO_DOC_DATA, CAMPO_DOC_VALOR
            , CONDICAO, ORIGEM_CONTA_CONTABIL, ID_CONTA_CONTABIL_OCC, ID_LANCAMENTO_TIPO, ID_TCI_FORMA_PAGAMENTO, ID_TCI_ORIGEM_PAGAMENTO
            , ID_TCI_ORIGEM, GERA_BORDERO, GERA_CHEQUE, CHEQUE_BENEFICIARIO, COMPLEMENTO, CAMPO_ID_PROJETO, CAMPO_ID_CONTA_CONTABIL
            , CAMPO_ID_PROJETO_META, VINCULAR_PROJETO, GERA_PAGAMENTO, TABELA_LANCAMENTO_TIPO, AGENDAMENTO, DIA
      FROM dbo.LANCAMENTO_CONFIGURACAO
      WHERE TABELA = @nomeTabela
         AND ID_TCI_ORIGEM_PAGAMENTO = @idTciOrigemPagamento
         AND (ID_TCI_FORMA_PAGAMENTO IS NULL OR ID_TCI_FORMA_PAGAMENTO = @idTciFormaPagamento)
      ORDER BY NUMERO_ORDEM
 
OPEN crLancamentoContabil

SET NOCOUNT ON

FETCH FIRST FROM crLancamentoContabil
INTO @id_lancamento_configuracao, @tabela, @tabelaProjeto, @tipo, @campo_doc_numero, @campo_doc_data, @campo_doc_valor, @condicao
   , @origem_conta_contabil, @id_conta_contabil_occ, @id_lancamento_tipo, @id_tci_forma_pagamento, @id_tci_origem_pagamento
   , @id_tci_origem, @gera_bordero, @gera_cheque, @cheque_bordero_beneficiario, @complemento, @nomeCampoProjeto, @nomeCampoContaContabil
   , @nomeCampoProjetoMeta, @vincularProjeto, @geraPagamento, @tabela_lancamento_tipo, @agendamento, @dia

WHILE @@FETCH_STATUS = 0
BEGIN
   BEGIN TRY
      --se o nome for diferente do padrão da meta
      IF(@idProjetoMeta IS NULL OR @nomeCampoProjetoMeta <> 'ID_PROJETO_META')
      BEGIN
         BEGIN TRY
            SELECT @sqlMeta = 'SELECT @projetoMeta = ' + ISNULL(@nomeCampoProjetoMeta,'ID_PROJETO_META') + ' '
                            + 'FROM dbo.' + @nomeTabela
                            + ' WHERE ID_' + @nomeTabela + ' = @id '
            SET @parametro = N'@id int, @projetoMeta int OUTPUT'
            EXECUTE sp_executesql  @sqlMeta
                                 , @parametro
                                 , @id = @idTabela
                                 , @projetoMeta=@idProjetoMeta OUTPUT
         END TRY
         BEGIN CATCH
            SET @idProjetoMeta = NULL
         END CATCH
      END
      
      IF(@idProjetoMeta IS NULL)
      BEGIN
         BEGIN TRY
            DECLARE @idTabelaProjeto integer
          
            --busca o nome do ID que será usado na busca da meta
            SELECT @sqlMeta = 'SELECT @idTab = ID_' + ISNULL(@tabelaProjeto,@nomeTabela) + ' '
                            + 'FROM dbo.' + @nomeTabela
                            + ' WHERE ID_' + @nomeTabela + ' = @id '
            SET @parametro = N'@id int, @idTab int OUTPUT'
            EXECUTE sp_executesql  @sqlMeta
                                 , @parametro
                                 , @id = @idTabela
                                 , @idTab=@idTabelaProjeto OUTPUT
                                          
            --busca a meta na tabela que faz referencia a que está sendo inserida
            SELECT @sqlMeta = 'SELECT @projetoMeta = ' + ISNULL(@nomeCampoProjetoMeta,'ID_PROJETO_META') + ' '
                            + 'FROM dbo.' + ISNULL(@tabelaProjeto,@nomeTabela)
                            + ' WHERE ID_' + ISNULL(@tabelaProjeto,@nomeTabela) + ' = @id '
            SET @parametro = N'@id int, @projetoMeta int OUTPUT'
            EXECUTE sp_executesql  @sqlMeta
                                 , @parametro
                                 , @id = @idTabelaProjeto
                                 , @projetoMeta=@idProjetoMeta OUTPUT
         END TRY
         BEGIN CATCH
            SET @idProjetoMeta = NULL
         END CATCH    
      END    

      IF (@idCentralDespesa IS NULL)
      BEGIN
         BEGIN TRY
            SET @sqlMeta = N'SELECT @CentralDespesa= cd.ID_CENTRAL_DESPESA '
                                + 'FROM dbo.' + @nomeTabela + ' t'
                                + '  INNER JOIN dbo.' + @tabelaProjeto + ' tp ON tp.ID_' + @tabelaProjeto + ' = t.ID_' + @tabelaProjeto + ' '
                                + '  INNER JOIN dbo.CENTRAL_DESPESA cd ON cd.ID_CENTRAL_DESPESA = tp.ID_CENTRAL_DESPESA '
                                --+ '  INNER JOIN dbo.CENTRAL_DESPESA_ITEM cdi ON cdi.ID_CENTRAL_DESPESA = cd.ID_CENTRAL_DESPESA '
                                + 'WHERE cd.DATA_HORA_FECHAMENTO IS NOT NULL '
                                + '  AND t.ID_' + @nomeTabela + ' = @id '
            SET @parametro = N'@id int, @CentralDespesa int OUTPUT'
            
            EXECUTE sp_executesql  @sqlMeta
                                 , @parametro
                                 , @id = @idTabela
                                 , @CentralDespesa=@idCentralDespesa OUTPUT
         END TRY
         BEGIN CATCH
            SET @idCentralDespesa = NULL
         END CATCH 
      END

      SELECT @tabela = dbo.fcRetiraQuebraDeLinha (@tabela)
      SELECT @tabelaProjeto = dbo.fcRetiraQuebraDeLinha (@tabelaProjeto)
      SELECT @tipo = dbo.fcRetiraQuebraDeLinha (@tipo)
      SELECT @campo_doc_numero = dbo.fcRetiraQuebraDeLinha (@campo_doc_numero)
      SELECT @campo_doc_data = dbo.fcRetiraQuebraDeLinha (@campo_doc_data)
      SELECT @campo_doc_valor = dbo.fcRetiraQuebraDeLinha (@campo_doc_valor)
      SELECT @condicao = dbo.fcRetiraQuebraDeLinha (@condicao)
      SELECT @origem_conta_contabil = dbo.fcRetiraQuebraDeLinha (@origem_conta_contabil)

      DECLARE @comando nvarchar(4000), @parametros nvarchar(4000), @lDocumentoData datetime, @lDocumentoNumero varchar(15), @lData datetime
            , @lValor numeric(18, 2), @lComplemento varchar(150), @lIdProjeto int, @lIdContaContabil int, @lIdCampo int
            , @lIdTciOrigemPagamento int, @lIdTciFormaPagamento int, @sqlJoinProjeto nvarchar(500), @sqlJoinPessoa nvarchar(500)

      SELECT @comando = NULL, @parametros = NULL, @lDocumentoData = NULL, @lDocumentoNumero = NULL, @lData = NULL, @lValor = NULL
           , @lComplemento = NULL, @lIdProjeto = NULL, @lIdContaContabil = NULL, @lIdCampo = NULL, @lIdTciOrigemPagamento = NULL
           , @lIdTciFormaPagamento = NULL, @sqlJoinProjeto = NULL, @sqlJoinPessoa = NULL

      SET @sqlJoinProjeto = ''
      SET @sqlJoinPessoa = ''
      IF(@tabelaProjeto IS NULL OR LTRIM(RTRIM(@tabelaProjeto)) = '')
      BEGIN
         IF(SELECT COUNT(*)
            FROM INFORMATION_SCHEMA.COLUMNS a
            WHERE 1=1
               AND UPPER(a.TABLE_NAME) = + @nomeTabela
               AND UPPER(a.COLUMN_NAME) = ISNULL(@nomeCampoProjeto, 'ID_PROJETO') + ' '
               AND a.TABLE_SCHEMA = 'DBO'    
            ) > 0
         BEGIN
            SET @sqlJoinProjeto += ' LEFT JOIN dbo.PROJETO p ON p.ID_PROJETO = t.' + ISNULL(@nomeCampoProjeto, 'ID_PROJETO') + ' '
         END
         IF(SELECT COUNT(*)
            FROM INFORMATION_SCHEMA.COLUMNS a
            WHERE 1=1
               AND UPPER(a.TABLE_NAME) = + @nomeTabela
               AND UPPER(a.COLUMN_NAME) = 'ID_PESSOA'
               AND a.TABLE_SCHEMA = 'DBO'    
            ) > 0
         BEGIN
            SET @sqlJoinPessoa += ' LEFT JOIN dbo.PESSOA pe ON pe.ID_PESSOA = t.ID_PESSOA '           
         END     
      END
      ELSE
      BEGIN
         SET @sqlJoinProjeto += ' LEFT JOIN dbo.' + @tabelaProjeto + ' tp ON tp.ID_' + @tabelaProjeto + ' = t.ID_' + @tabelaProjeto
       
         IF(SELECT COUNT(*)
            FROM INFORMATION_SCHEMA.COLUMNS a
            WHERE 1=1
               AND UPPER(a.TABLE_NAME) = @tabelaProjeto
               AND UPPER(a.COLUMN_NAME) = ISNULL(@nomeCampoProjeto, 'ID_PROJETO') + ' '
               AND a.TABLE_SCHEMA = 'dbo'    
            ) > 0
         BEGIN
            SET @sqlJoinProjeto += ' LEFT JOIN dbo.PROJETO p ON p.ID_PROJETO = tp.ID_PROJETO '
         END -- senao verifica na tabela de origem
         ELSE IF(SELECT COUNT(*)
            FROM INFORMATION_SCHEMA.COLUMNS a
            WHERE 1=1
               AND UPPER(a.TABLE_NAME) = @nomeTabela
               AND UPPER(a.COLUMN_NAME) = 'ID_PROJETO'
               AND a.TABLE_SCHEMA = 'dbo'    
            ) > 0
         BEGIN
            SET @sqlJoinProjeto += ' LEFT JOIN dbo.PROJETO p ON p.ID_PROJETO = t.' + ISNULL(@nomeCampoProjeto, 'ID_PROJETO')
         END
       
         IF(SELECT COUNT(*)
            FROM INFORMATION_SCHEMA.COLUMNS a
            WHERE 1=1
               AND UPPER(a.TABLE_NAME) = @nomeTabela
               AND UPPER(a.COLUMN_NAME) = 'ID_PESSOA'
               AND a.TABLE_SCHEMA = 'dbo'    
            ) > 0
         BEGIN
            SET @sqlJoinPessoa += ' LEFT JOIN dbo.PESSOA pe ON pe.ID_PESSOA = t.ID_PESSOA '           
         END -- senao verifica na tabela com relacionamento do projeto
         ELSE IF(SELECT COUNT(*)
            FROM INFORMATION_SCHEMA.COLUMNS a
            WHERE 1=1
               AND UPPER(a.TABLE_NAME) = @tabelaProjeto
               AND UPPER(a.COLUMN_NAME) = 'ID_PESSOA'
               AND a.TABLE_SCHEMA = 'dbo'    
            ) > 0
         BEGIN
            SET @sqlJoinPessoa += ' LEFT JOIN dbo.PESSOA pe ON pe.ID_PESSOA = tp.ID_PESSOA '           
         END 

      END

       SET @comando = N'SELECT  @idCampoOUT=t.ID_' + @nomeTabela
                    +', @lIdTciFormaPagamentoOUT=t.ID_TCI_FORMA_PAGAMENTO'
                    +', @lIdTciOrigemPagamentoOUT=t.ID_TCI_ORIGEM_PAGAMENTO'
                    +', @lIdProjetoOUT=' + CASE WHEN @sqlJoinProjeto <> '' THEN 'p.ID_PROJETO' ELSE 'NULL' END
                    +', @lDocumentoDataOUT=' + CASE WHEN @campo_doc_data <> '' THEN + 't.' + @campo_doc_data ELSE 'NULL' END
                    +', @lDocumentoNumeroOUT=' + CASE WHEN @campo_doc_numero <> '' THEN + 't.' + @campo_doc_numero ELSE 'NULL' END
                    +', @lValorOUT=t.' + @campo_doc_valor
                    +', @lIdPessoaOUT=' + CASE WHEN @sqlJoinPessoa <> '' THEN 'pe.ID_PESSOA' ELSE 'NULL' END
                    +', @lNomePessoaOUT=' + CASE WHEN @sqlJoinPessoa <> '' THEN 'pe.NOME' ELSE 'NULL' END
                    +', @IdFundacaoOUT=' + CASE WHEN @tabelaProjeto IS NULL OR LTRIM(RTRIM(@tabelaProjeto)) = '' THEN 't.ID_FUNDACAO' ELSE 'tp.ID_FUNDACAO' END

       SET @parametros = N'@id int'
                       +', @lIdTciFormaPagamentoOUT int OUTPUT'
                       +', @lIdTciOrigemPagamentoOUT int OUTPUT'
                       +', @lIdProjetoOUT int OUTPUT'
                       +', @idCampoOUT int OUTPUT'
                       +', @lDocumentoDataOUT datetime OUTPUT'
                       +', @lDocumentoNumeroOUT varchar(15) OUTPUT'
                       +', @lValorOUT numeric(18, 2) OUTPUT'
                       +', @lIdPessoaOUT int OUTPUT'
                       +', @lNomePessoaOUT varchar(300) OUTPUT'
                       +', @IdFundacaoOUT int OUTPUT'

      SET @comando = @comando
                   + ' FROM dbo.' + @nomeTabela + ' t '
                   + @sqlJoinProjeto
                   + @sqlJoinPessoa
                    + ' WHERE t.ID_' + @nomeTabela + ' = @id '

      IF(@condicao IS NOT NULL AND LTRIM(RTRIM(@condicao)) <> '')
         SET @comando += @condicao

       EXECUTE sp_executesql  @comando
                            , @parametros
                            , @id=@idTabela
                            , @lIdTciFormaPagamentoOUT=@lIdTciFormaPagamento OUTPUT
                            , @lIdTciOrigemPagamentoOUT=@lIdTciOrigemPagamento OUTPUT
                            , @lIdProjetoOUT=@lIdProjeto OUTPUT
                            , @idCampoOUT=@lIdCampo OUTPUT
                            , @lDocumentoDataOUT=@lDocumentoData OUTPUT
                            , @lDocumentoNumeroOUT=@lDocumentoNumero OUTPUT
                            , @lValorOUT=@lValor OUTPUT
                            , @lIdPessoaOUT=@lIdPessoa OUTPUT
                            , @lNomePessoaOUT=@lNomePessoa OUTPUT
                            , @IdFundacaoOUT=@idFundacao OUTPUT
 
      IF(@lValor IS NOT NULL AND @lValor > 0)
      BEGIN

         IF(@usarDataSistemaParaLancamento = 'S' AND @permiteDataDocPosterior = 'N')
         BEGIN
            IF(@lDocumentoData > @dataHoraLancamento)
            BEGIN
               ROLLBACK TRANSACTION
               SET @retorno = 150 --A Data do Documento não pode ser maior que a Data do Lançamento
               CLOSE crLancamentoContabil
               DEALLOCATE crLancamentoContabil
               RETURN
            END
         END   

         --se for para não vincular o projeto ao lançamento, seta como nulo
         IF(@vincularProjeto = 'N')
         BEGIN
            SET @lIdProjeto = NULL
            SET @idProjetoMeta = NULL
         END

         IF(@origem_conta_contabil='D') --Conta Contabil DIGITADA (tabela)
         BEGIN
            DECLARE @sqlContabil nvarchar(500), @parametroContabil nvarchar(500)
            SET @sqlContabil = N'SELECT @lIdContaContabilOUT=' + ISNULL(@nomeCampoContaContabil, 'ID_CONTA_CONTABIL') + ' '
                             + 'FROM dbo.' + @nomeTabela + ' '
                             + 'WHERE ID_' + @nomeTabela + ' = @id '
            SET @parametroContabil = N'@id int, @lIdContaContabilOUT int OUTPUT'
            
            BEGIN TRY
               EXECUTE sp_executesql  @sqlContabil
                                     , @parametroContabil
                                     , @id=@idTabela
                                     , @lIdContaContabilOUT=@lIdContaContabil OUTPUT
            END TRY
            BEGIN CATCH
               SET @sqlContabil = N'SELECT @lIdContaContabilOUT=' + ISNULL(@nomeCampoContaContabil, 'ID_CONTA_CONTABIL') + ' '
                                + 'FROM dbo.' + @nomeTabela + ' t'
                                + ' INNER JOIN dbo.' + @tabelaProjeto + ' tp ON tp.ID_' + @tabelaProjeto + ' = t.ID_' + @tabelaProjeto + ' '
                                + 'WHERE t.ID_' + @nomeTabela + ' = @id '
               EXECUTE sp_executesql  @sqlContabil
                                     , @parametroContabil
                                     , @id=@idTabela
                                     , @lIdContaContabilOUT=@lIdContaContabil OUTPUT
            END CATCH
            

            IF(@lIdContaContabil IS NULL)
            BEGIN
               ROLLBACK TRANSACTION
               SET @retorno = 25 --É obrigatório o preenchimento da Conta Contábil
               CLOSE crLancamentoContabil
               DEALLOCATE crLancamentoContabil
               RETURN
            END
         END --IF(@origem_conta_contabil='D') --Conta Contabil DIGITADA (tabela)
         ELSE IF(@origem_conta_contabil = 'P') --Conta Contabil PROJETO (tabela)
         BEGIN
            SET @lIdContaContabil = NULL
            IF(@idProjetoMeta IS NOT NULL)
            BEGIN
               SELECT @lIdContaContabil=ID_CONTA_CONTABIL
               FROM dbo.PROJETO_META
               WHERE ID_PROJETO_META = @idProjetoMeta
            END
            
            --SE NÃO ACHOU A CC DA META, BUSCA DO PROJETO
            IF(@lIdContaContabil IS NULL)
            BEGIN
               IF (@lIdProjeto IS NULL) --se o projeto eh nulo busca a Conta da Fundação
               BEGIN
                  SELECT @lIdContaContabil=ID_CONTA_CONTABIL
                  FROM dbo.FUNDACAO
                  WHERE ID_FUNDACAO = @idFundacao
               END
               ELSE
               BEGIN
                  SELECT @lIdContaContabil=ID_CONTA_CONTABIL
                  FROM dbo.PROJETO
                  WHERE ID_PROJETO = @lIdProjeto
                 
                  IF(@lIdContaContabil IS NULL)
                  BEGIN
                    ROLLBACK TRANSACTION
                       SET @retorno = 8 --Não foi possível gerar os lançamentos. Projeto sem Conta Contábil cadastrada
                    CLOSE crLancamentoContabil
                    DEALLOCATE crLancamentoContabil
                    RETURN             
                  END
               END
            END--IF(@lIdContaContabil IS NULL)
         END--ELSE IF(@origem_conta_contabil = 'P') --Conta Contabil PROJETO (tabela)
         ELSE IF(@origem_conta_contabil = 'F') --Conta Contabil FUNDACAO - CONTA GERAL
         BEGIN
            SELECT @lIdContaContabil=ID_CONTA_CONTABIL
            FROM dbo.FUNDACAO
             WHERE ID_FUNDACAO = @idFundacao
         END
         ELSE
            SET @lIdContaContabil = @id_conta_contabil_occ

         IF(@id_tci_forma_Pagamento IS NULL OR (@id_tci_forma_Pagamento = @lIdTciFormaPagamento))
         BEGIN
       
            SET @lDocumentoData = CASE WHEN @lDocumentoData IS NOT NULL THEN @lDocumentoData ELSE GETDATE() END
            SET @cont += 1
          
            --se não for um historico padrão, busca na tabela de configuração a origem
            IF(@id_lancamento_tipo IS NULL AND @tabela_lancamento_tipo IS NOT NULL)
            BEGIN
               DECLARE @sqlHistorico nvarchar(500), @parametroHistorico nvarchar(500)
               IF (@nomeTabela = @tabela_lancamento_tipo)
               BEGIN
                  SET @sqlHistorico = N'SELECT @lIdLancamentoTipoOUT=t.ID_LANCAMENTO_TIPO '
                                    + 'FROM dbo.' + @nomeTabela + ' t '
                                    + 'WHERE ID_' + @nomeTabela + ' = @id '
               END
               ELSE
               BEGIN
                  SET @sqlHistorico = N'SELECT @lIdLancamentoTipoOUT=tl.ID_LANCAMENTO_TIPO '
                                    + 'FROM dbo.' + @nomeTabela + ' t '
                                    + '  INNER JOIN ' + @tabelaProjeto + ' tp ON tp.ID_' + @tabelaProjeto + ' = t.ID_'+ @tabelaProjeto + ' '
                                    + '  INNER JOIN ' + @tabela_lancamento_tipo + ' tl ON tl.ID_' + @tabela_lancamento_tipo + ' = tp.ID_'+ @tabela_lancamento_tipo + ' '
                                    + 'WHERE ID_' + @nomeTabela + ' = @id '               
               END
               SET @parametroHistorico = N'@id int, @lIdLancamentoTipoOUT int OUTPUT'
                EXECUTE sp_executesql  @sqlHistorico
                                     , @parametroHistorico
                                     , @id=@idTabela
                                     , @lIdLancamentoTipoOUT=@id_lancamento_tipo OUTPUT       
            END
          
            --zera os valores antes de buscar
            SELECT @contaAtiva  = 'S'
               , @saldoContaContabil  = 0
               , @validarLancamento  = 'S'
               , @tipoProjeto = NULL
               , @classificador1 = NULL
          
            SELECT @contaAtiva = pcc.ATIVO
               , @saldoContaContabil = ISNULL(pcc.VALOR_SALDO,0)
               , @validarLancamento = ISNULL(p.VALIDAR_VALORES_PARA_LANCAMENTO,'S')
               , @tipoProjeto = TIPO
               , @classificador1 = cc.CLASSIFICADOR1
               , @valorSaldoProjeto = ISNULL(p.VALOR_SALDO,0) + ISNULL(p.VALOR_A_REALIZAR,0)
               , @codigoContabil = cc.CODIGO
               , @contaCorrenteRubrica = cc.BANCO_CONTA
               , @contaCorrenteProjeto = p.BANCO_CONTA
               , @siconv = ISNULL(p.SICONV,'N')
            FROM PROJETO_CONTA_CONTABIL pcc
               INNER JOIN PROJETO p ON p.ID_PROJETO = pcc.ID_PROJETO
               INNER JOIN CONTA_CONTABIL cc ON cc.ID_CONTA_CONTABIL = pcc.ID_CONTA_CONTABIL
            WHERE pcc.ID_PROJETO = @lIdProjeto
            AND pcc.ID_CONTA_CONTABIL = @lIdContaContabil
          
            --se o projeto for SICONV nao permite algumas forma de pagamento
            IF(@siconv = 'S' AND (SELECT dbo.fcBuscarValorParametro('PROJETO', 'SICONV_FORMA_PAGTO_NAO_PERMITIDA')) LIKE '%'+CONVERT(varchar(10),@idTciFormaPagamento)+'%')
            BEGIN
               ROLLBACK TRANSACTION
               SET @retorno = 121 --Projeto do tipo SICONV não permite essa Forma de Pagamento
               CLOSE crLancamentoContabil
               DEALLOCATE crLancamentoContabil
               RETURN
            END
          
            --verifica se a meta eh realmente do projeto
            IF(@idProjetoMeta IS NOT NULL AND @idProjetoMeta > 0)
            BEGIN
               IF EXISTS (SELECT 1 FROM dbo.PROJETO_META WHERE ID_PROJETO = @lIdProjeto AND ID_PROJETO_META = @idProjetoMeta)
                  SET @idProjetoMetaLancamento = @idProjetoMeta
               ELSE
                  SET @idProjetoMetaLancamento = NULL
            END
            ELSE
               SET @idProjetoMetaLancamento = NULL
               
            IF(@lIdProjeto IS NOT NULL AND @idProjetoMetaLancamento IS NULL AND @nomeTabela = 'CONTA_CONTABIL_EXTRATO')
            BEGIN
               SELECT @idProjetoMetaLancamento = ID_PROJETO_META
               FROM dbo.PROJETO_META
               WHERE ID_PROJETO = @lIdProjeto
                  AND NUMERO = 1
            END
            
            --excessão a regra, esta conta 3 deve ter um projeto relacionado
            IF(@lIdContaContabil = (SELECT CONVERT(integer, STR(dbo.fcBuscarValorParametro('LANCAMENTO', 'CONTA_RELACIONADA_PROJETO'),6,0)))
               AND @lIdProjeto IS NULL)
            BEGIN
               ROLLBACK TRANSACTION
               SET @retorno = 46 --Não é permitido gerar Lançamentos para a conta 311.102 sem Projeto relacionado
               CLOSE crLancamentoContabil
               DEALLOCATE crLancamentoContabil
               RETURN
            END        
       
            IF(@lIdPessoa IS NOT NULL)
            BEGIN
               SELECT @cpfCnpj = CPF_CNPJ
                  , @idPessoaFuncionario = case when pf.ID_TBI_CARGO_NATUREZA = (isnull((select dbo.fcBuscarTabelaBasicaItemPorCodigo('PESSOA_CARGO_NATUREZA','RPA')),0)) then null else pf.ID_PESSOA_FUNCIONARIO end
                  , @estrangeiro = ISNULL(p.ESTRANGEIRO,'N')
                  , @pisPasep = CASE WHEN p.TIPO = 'F' THEN pfi.PIS_PASEP ELSE '00000000000' END
               FROM PESSOA p
                  LEFT JOIN PESSOA_FUNCIONARIO pf ON pf.ID_PESSOA = p.ID_PESSOA AND 
				                                     pf.DATA_DEMISSAO IS NULL and 
													 pf.DATA_MOVIMENTACAO is null and
													 pf.ID_PESSOA = pf.ID_PESSOA_MASTER 
                  LEFT JOIN PESSOA_FISICA pfi ON pfi.ID_PESSOA = p.ID_PESSOA
               WHERE p.ID_PESSOA = @lIdPessoa

               IF((@cpfCnpj IS NULL OR LTRIM(RTRIM(@cpfCnpj)) = '') AND @estrangeiro = 'N'
                  AND @nomeTabela <> 'ADIANTAMENTO_RECIBO' )
               BEGIN
                  ROLLBACK TRANSACTION
                  SET @retorno = 39 --Não é permitido gerar Lançamentos para Pessoa sem CPF/CNPJ
                  CLOSE crLancamentoContabil
                  DEALLOCATE crLancamentoContabil
                  RETURN
               END
             
               --se for um campo de ISS ou ISSQN valida para ver se pessoa possui PIS/PASEP
               IF ((SELECT PATINDEX('%ISS%',@campo_doc_valor) ) > 0 
                     AND ((@pisPasep IS NULL OR LEN(LTRIM(RTRIM(@pisPasep))) < 11) AND @estrangeiro = 'N')
                     AND @nomeTabela IN ('RPA_RPS', 'BOLSA')) 
               BEGIN
                  ROLLBACK TRANSACTION
                  SET @retorno = 52 --A Pessoa informada não possui PIS/PASEP cadastrado. Não é possível gerar os lançamentos.
                  CLOSE crLancamentoContabil
                  DEALLOCATE crLancamentoContabil
                  RETURN
               END             
             
               IF(@idPessoaFuncionario IS NOT NULL AND @nomeTabela IN ('RPA_RPS', 'BOLSA'))
               BEGIN
                  ROLLBACK TRANSACTION
                  SET @retorno = 45 --A Pessoa informada é funcionário da Fundação. Não é possível gerar os lançamentos.
                  CLOSE crLancamentoContabil
                  DEALLOCATE crLancamentoContabil
                  RETURN
               END               
            END
           
            --altera a string do complemento com os dados do lançamento
            DECLARE @sqlComplemento nvarchar(300), @parametroComplemento nvarchar(100), @nomeCampo varchar(300), @valorCampo varchar(300)
            WHILE (PATINDEX('%{%',@complemento) > 0)
            BEGIN
               --enquanto houver {} pegar o campo da tabela que esta neste intervalo e setar no complemento
             
               SELECT @nomeCampo = SUBSTRING(@complemento
                                            ,PATINDEX('%{%',@complemento)+1
                                            ,PATINDEX('%}%',@complemento)-PATINDEX('%{%',@complemento)-1)
             
               SET @sqlComplemento = N'SELECT @lvalorCampoOUT= CONVERT(varchar(300),' + @nomeCampo + ')'
                                 + 'FROM dbo.' + @nomeTabela + ' '
                                 + 'WHERE ID_' + @nomeTabela + ' = @id '
               SET @parametroComplemento = N'@id int, @lvalorCampoOUT varchar(300) OUTPUT'
               EXECUTE sp_executesql  @sqlComplemento
                                    , @parametroComplemento
                                    , @id=@idTabela
                                    , @lvalorCampoOUT=@valorCampo OUTPUT
                                  
               SET @complemento = REPLACE(@complemento, '{'+@nomeCampo+'}', ISNULL(@valorCampo,''))
            END

            --Verifica se necessita ter CENTRAL DESPESA
            IF(@idTciOrigemLancamento <> @idTciOrigemLancamentoLivre)
            BEGIN
               IF EXISTS (SELECT TOP 1 pcc.ID_PROJETO_CONTA_CONTABIL
                          FROM PROJETO_CONTA_CONTABIL pcc
                             INNER JOIN PROJETO_CONTA_CONTABIL_ITEM pcci ON pcci.ID_PROJETO_CONTA_CONTABIL = pcc.ID_PROJETO_CONTA_CONTABIL
                          WHERE pcc.ID_PROJETO = @lIdProjeto
                             AND pcc.ID_CONTA_CONTABIL = @lIdContaContabil
                          )
               BEGIN
                  IF(@idCentralDespesa IS NULL
                     OR (SELECT DATA_HORA_FECHAMENTO FROM CENTRAL_DESPESA WHERE ID_CENTRAL_DESPESA = @idCentralDespesa) IS NULL
                     )
                  BEGIN
                     ROLLBACK TRANSACTION
                     SET @retorno = 55 --'Não é permitido gerar Lançamentos para esta rubrica pois deve ser registrada na Central Despesa.'
                     CLOSE crLancamentoContabil
                     DEALLOCATE crLancamentoContabil
                     RETURN
                  END
               END      
            END   

            --corrige a string do complemento, substituindo os valores
            SET @complemento = REPLACE(@complemento, '[PESSOA]', ISNULL(@lNomePessoa,''))
            SET @complemento = REPLACE(@complemento, '[MES]', ISNULL(@mes,''))
            SET @complemento = REPLACE(@complemento, '[ANO]', ISNULL(@ano,''))
            SET @complemento = REPLACE(@complemento, '[DOCUMENTO_NUMERO]', ISNULL(@lDocumentoNumero,''))
            SET @complemento = REPLACE(@complemento, '[CONTA_CORRENTE_RUBRICA]', ISNULL(@contaCorrenteRubrica,''))
            SET @complemento = REPLACE(@complemento, '[CONTA_CORRENTE_PROJETO]', ISNULL(@contaCorrenteProjeto,''))
          
            SET @lDocumentoData = CONVERT(date, @lDocumentoData)

            IF(@agendamento = 'S')
            BEGIN

               IF(@dia IS NULL OR @dia = 0)
                  SET @dataAgendamento = dbo.fcGetProximoDiaUtil(GETDATE()+1)
               ELSE 
               BEGIN
                  NOVADATA:
                  SELECT @dataAgendamento = CONVERT(varchar(2),ISNULL(@dia,1))
                                          + '/' + CONVERT(varchar(2),DATEPART(MONTH,DATEADD(MONTH,1,GETDATE())))
                                          + '/' + CONVERT(varchar(4),YEAR(GETDATE()))
                  WHILE(ISDATE(@dataAgendamento) = 0)
                  BEGIN
                     SET @dia -= 1
                     GOTO NOVADATA
                  END
               END
               
               SET @GerarDocPagamento = CASE @idTciFormaPagamento WHEN dbo.fcBuscarTabelaCampoItemPorNome('LANCAMENTO', 'FORMA_PAGAMENTO', 'BORDERO')  THEN 'B'
                                                                  WHEN dbo.fcBuscarTabelaCampoItemPorNome('LANCAMENTO', 'FORMA_PAGAMENTO', 'CHEQUE')   THEN 'C'
                                                                  WHEN dbo.fcBuscarTabelaCampoItemPorNome('LANCAMENTO', 'FORMA_PAGAMENTO', 'OFICIO')  THEN 'P'
                                        ELSE 'N' END --não gerar nada

               INSERT INTO dbo.AGENDAMENTO
                  (DEBITO_CREDITO
                  ,GERAR_DOC_PAGAMENTO
                  ,DOCUMENTO_DATA
                  ,DOCUMENTO_NUMERO
                  ,COMPLEMENTO
                  ,VALOR
                  ,DATA
                  ,DATA_HORA_CADASTRO
                  ,DATA_HORA_ALTERACAO
                  ,DATA_HORA_LANCAMENTO
                  ,ID_PROJETO
                  ,ID_PROJETO_META
                  ,ID_CONTA_CONTABIL
                  ,ID_PESSOA
                  ,ID_LANCAMENTO_TIPO
                  ,ID
                  ,ID_TCI_ORIGEM
                  ,ID_USUARIO_CADASTRO
                  ,ID_USUARIO_ALTERACAO
                  ,ID_USUARIO_LANCAMENTO
                  ,ID_TCI_ORIGEM_PAGAMENTO
                  ,ID_TCI_FORMA_PAGAMENTO
                  ,ID_FUNDACAO
                  )
               VALUES (@tipo --DEBITO_CREDITO
                  ,@GerarDocPagamento --GERAR_DOC_PAGAMENTO
                  ,@lDocumentoData --DOCUMENTO_DATA
                  ,@lDocumentoNumero --DOCUMENTO_NUMERO
                  ,@complemento --COMPLEMENTO
                  ,@lValor --VALOR
                  ,CONVERT(datetime,@dataAgendamento) --DATA
                  ,GETDATE() --DATA_HORA_CADASTRO
                  ,NULL --DATA_HORA_ALTERACAO
                  ,NULL --DATA_HORA_LANCAMENTO
                  ,@lIdProjeto --ID_PROJETO
                  ,@idProjetoMetaLancamento --ID_PROJETO_META
                  ,@lIdContaContabil --ID_CONTA_CONTABIL
                  ,@lIdPessoa --ID_PESSOA
                  ,@id_lancamento_tipo --ID_LANCAMENTO_TIPO
                  ,@idTabela --ID
                  ,@id_tci_origem --ID_TCI_ORIGEM
                  ,@idUsuario --ID_USUARIO
                  ,NULL --ID_USUARIO_ALTERACAO
                  ,NULL --ID_USUARIO_LANCAMENTO
                  ,@idTciOrigemPagamento --ID_TCI_ORIGEM_PAGAMENTO
                  ,@idTciFormaPagamento --ID_TCI_FORMA_PAGAMENTO
                  ,@idFundacao --ID_FUNDACAO
				  )

            END
            ELSE --gera o registro em Lançamento
            BEGIN
               EXEC dbo.spInserirLancamento
                           @id_lancamento OUTPUT
                         , @retorno OUTPUT
                         , @tipo
                         , @lDocumentoData
                         , @lDocumentoNumero
                         , @dataHoraLancamento
                         , @lValor
                         , @complemento
                         , @lIdProjeto
                         , @lIdContaContabil
                         , @id_lancamento_tipo
                         , @idTabela
                         , @lIdPessoa
                         , @idUsuario
                         , 'INSERT'
                         , @id_tci_origem
                         , @idProjetoMetaLancamento
                         , @idFundacao

               IF(@retorno > 0)
               BEGIN
                  ROLLBACK TRANSACTION
                  CLOSE crLancamentoContabil
                  DEALLOCATE crLancamentoContabil
                  RETURN
               END 
           
               IF(@geraPagamento = 'S')
               BEGIN
                  SELECT @liberarPgtoPessoa = ISNULL(LIBERAR_PAGAMENTO,'N') FROM PESSOA WHERE ID_PESSOA = @lIdPessoa
                  IF(@liberarPgtoPessoa = 'N')
                  BEGIN
                     ROLLBACK TRANSACTION
                     SET @retorno = 164 --Esta Pessoa não está liberada para receber Pagamentos.'
                     CLOSE crLancamentoContabil
                     DEALLOCATE crLancamentoContabil
                     RETURN
                  END               
               
                  EXEC dbo.spInserirPagamento @id_lancamento, @nomeTabela
               END
              
               IF(@gera_cheque = 'S')
               BEGIN
                  SET @idPessoaBeneficiario = NULL
             
                  IF (@cheque_bordero_beneficiario = 'F' OR @BeneficiarioCheque = 'F') -- cheque nominal para a FUNDACAO
                     SELECT @idPessoaBeneficiario = ID_PESSOA FROM dbo.FUNDACAO WHERE ID_FUNDACAO = @idFundacao
                  ELSE IF (@cheque_bordero_beneficiario = 'U' OR @BeneficiarioCheque = 'U') -- cheque nominal para a UNIVERSIDADE
                     SELECT @idPessoaBeneficiario = CONVERT(integer, STR(dbo.fcBuscarValorParametro('SISTEMA', 'PESSOA_UNIVERSIDADE'),6,0))
                  ELSE IF (@cheque_bordero_beneficiario = 'P' OR @BeneficiarioCheque = 'P') -- cheque nominal para a PESSOA
                     SET @idPessoaBeneficiario = @lIdPessoa
                  ELSE IF (@cheque_bordero_beneficiario = 'C' OR @BeneficiarioCheque = 'C') -- cheque nominal para ao COORDENADOR DO PROJETO
                     SELECT @idPessoaBeneficiario = ID_PESSOA_COORDENADOR FROM dbo.PROJETO WHERE ID_PROJETO = @lIdProjeto
                  ELSE
                     SET @idPessoaBeneficiario = @lIdPessoa  
                     
                  SELECT @liberarPgtoPessoa = ISNULL(LIBERAR_PAGAMENTO,'N') FROM PESSOA WHERE ID_PESSOA = @idPessoaBeneficiario
                  IF(@liberarPgtoPessoa = 'N')
                  BEGIN
                     ROLLBACK TRANSACTION
                     SET @retorno = 164 --Esta Pessoa não está liberada para receber Pagamentos.'
                     CLOSE crLancamentoContabil
                     DEALLOCATE crLancamentoContabil
                     RETURN
                  END
                
                  --usa a funcao para gerar o cheque
                  EXEC dbo.spGerarCheque @idPessoaBeneficiario, @id_lancamento, @lNomePessoa
               END --IF(@gera_cheque = 'S')
          
               IF(@gera_bordero = 'S') --usa a funcao para gerar o bordero
               BEGIN
                  SET @idPessoaBeneficiario = NULL
             
                  IF (@cheque_bordero_beneficiario = 'F') -- cheque nominal para a FUNDACAO
                     SELECT @idPessoaBeneficiario = ID_PESSOA FROM dbo.FUNDACAO WHERE ID_FUNDACAO = @idFundacao
                  ELSE IF (@cheque_bordero_beneficiario = 'U') -- cheque nominal para a UNIVERSIDADE
                     SELECT @idPessoaBeneficiario = CONVERT(integer, STR(dbo.fcBuscarValorParametro('SISTEMA', 'PESSOA_UNIVERSIDADE'),6,0))
                  ELSE IF (@cheque_bordero_beneficiario = 'P') -- cheque nominal para a PESSOA
                     SET @idPessoaBeneficiario = ISNULL(@idPessoaBordero,@lIdPessoa)
                  ELSE IF (@cheque_bordero_beneficiario = 'C') -- cheque nominal para ao COORDENADOR DO PROJETO
                     SELECT @idPessoaBeneficiario = ID_PESSOA_COORDENADOR FROM dbo.PROJETO WHERE ID_PROJETO = @lIdProjeto
                  ELSE
                     SET @idPessoaBeneficiario = ISNULL(@idPessoaBordero,@lIdPessoa)
                   
                  SELECT @liberarPgtoPessoa = ISNULL(LIBERAR_PAGAMENTO,'N') FROM PESSOA WHERE ID_PESSOA = @idPessoaBeneficiario
                  IF(@liberarPgtoPessoa = 'N')
                  BEGIN
                     ROLLBACK TRANSACTION
                     SET @retorno = 164 --Esta Pessoa não está liberada para receber Pagamentos.'
                     CLOSE crLancamentoContabil
                     DEALLOCATE crLancamentoContabil
                     RETURN
                  END                   
                   
                  EXEC dbo.spInserirBordero @id_lancamento, @idPessoaBeneficiario, @nomeTabela, @retorno OUTPUT
                  --se um dos dados bancários não existir, não deixar gerar lançamento para pagamento por borderô
                  IF(@retorno > 0)
                  BEGIN
                     ROLLBACK TRANSACTION
                     CLOSE crLancamentoContabil
                     DEALLOCATE crLancamentoContabil
                     RETURN
                  END               
               END --IF(@gera_bordero = 'S')
            END--ELSE IF(@agendamento = 'S')
         END 
      END
   END TRY
   BEGIN CATCH
      ROLLBACK TRANSACTION
      SET @retorno = 5 --Erro ao Gerar os Lançamentos
      CLOSE crLancamentoContabil
      DEALLOCATE crLancamentoContabil
      RETURN
   END CATCH

    FETCH NEXT FROM crLancamentoContabil
   INTO @id_lancamento_configuracao, @tabela, @tabelaProjeto, @tipo, @campo_doc_numero, @campo_doc_data, @campo_doc_valor, @condicao
      , @origem_conta_contabil, @id_conta_contabil_occ, @id_lancamento_tipo, @id_tci_forma_pagamento, @id_tci_origem_pagamento
      , @id_tci_origem, @gera_bordero, @gera_cheque, @cheque_bordero_beneficiario, @complemento, @nomeCampoProjeto, @nomeCampoContaContabil
      , @nomeCampoProjetoMeta, @vincularProjeto, @geraPagamento, @tabela_lancamento_tipo, @agendamento, @dia
END
IF(@cont = 0 AND @retorno = 0)
BEGIN
   ROLLBACK TRANSACTION
   SET @retorno = 9 --Não existem parâmetros para geração dos lançamentos
   CLOSE crLancamentoContabil
   DEALLOCATE crLancamentoContabil
   RETURN
END

CLOSE crLancamentoContabil
DEALLOCATE crLancamentoContabil
 
IF(@retorno = 0)
BEGIN

   DECLARE @sqlLancamento nvarchar(1000)
   SET @sqlLancamento =N' UPDATE dbo.' + @nomeTabela
                      + ' SET DATA_HORA_LANCAMENTO = ''' + CONVERT(nvarchar(30), @dataHoraLancamento, 126) + ''''
                      + ' , ID_USUARIO_LANCAMENTO = ' + CONVERT(nvarchar(10),@idUsuario)
                      + ' WHERE ID_' + @nomeTabela + ' =  ' + CONVERT(nvarchar(10),@idTabela)
   EXECUTE sp_executesql  @sqlLancamento
   
   COMMIT TRANSACTION
END
ELSE
BEGIN
   ROLLBACK TRANSACTION
   SET @retorno = 1 --Erro não identificado
   RETURN
END