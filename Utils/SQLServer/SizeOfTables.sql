-- =====================================================================
-- Author: Fernando Prass | Create date: 10/07/2016
-- Language: T-SQL for SQL Server 2005+
-- Description: Determine how much space on disk each table is consuming
-- Contact: https://gitlab.com/fernando.prass or https://twitter.com/oFernandoPrass
-- =====================================================================

declare @tableName sysname, @schemaName sysname

create table #tmpTamTabela(
	  name       sysname     null
	, rows       int         null
	, reserved   varchar(25) null
	, data       varchar(25) null
	, index_size varchar(25) null
	, unused     varchar(25) null )
 
declare crsrTables cursor local fast_forward read_only for
   select TABLE_SCHEMA, TABLE_NAME
   from information_schema.TABLES
   order by TABLE_SCHEMA, TABLE_NAME
 
open crsrTables
 
while 1 = 1
begin
   fetch next from crsrTables into @schemaName, @tableName
   if @@fetch_status <> 0 
   break

   set @tableName = @schemaName+'.'+@tableName
   insert into #tmpTamTabela (name, rows, reserved, data, index_size, unused)
   exec sp_spaceused @tableName
 
end
close crsrTables
deallocate crsrTables
 
select name as 'TableName'
      , rows as 'Rows'
      , convert(int, replace(reserved, ' KB','')) as 'TotalSizeKB'
      , convert(int, replace(data, ' KB',''))as 'DataSizeKB'
      , convert(int, replace(index_size, ' KB',''))as 'IndexSizeKB'
      , convert(int, replace(unused, ' KB',''))as 'UnusedKB'
   from #tmpTamTabela
order by name, convert(int, replace(reserved, ' KB','')) desc

drop table #tmpTamTabela
   