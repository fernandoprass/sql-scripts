-- =====================================================================
-- Author: Fernando Prass | Create date: 03/11/2012
-- Language: T-SQL for SQL Server 2010+
-- Description: Create and populate a time dimension for data warehouses
-- Contact: https://gitlab.com/fernando.prass or https://twitter.com/oFernandoPrass
-- More information (in Portuguese): http://fp2.com.br/blog/index.php/2012/script-para-popular-dimensao-tempo-data/#more-79
-- =====================================================================


CREATE TABLE DIM_TIME(
	ID_DIM_TIME int IDENTITY(1,1) NOT NULL PRIMARY KEY,
	DATE_SMALL date NOT NULL,
	NUMBER_YEAR smallint NOT NULL,
	MONTH_OF_YEAR smallint NOT NULL,
	DAY_OF_MONTH smallint NOT NULL,
	DAY_OF_WEEK smallint NOT NULL,
	DAY_OF_YEAR smallint NOT NULL,
	LEAP_YEAR BIT NOT NULL,
	WORKDAY BIT NOT NULL,
	WEEKEND BIT NOT NULL,
	HOLIDAY BIT NOT NULL,
	PRE_HOLIDAY BIT NOT NULL,
	POS_HOLIDAY BIT NOT NULL,
	HOLIDAY_NAME varchar(30) NULL,
	DAY_OF_WEEK_NAME varchar(15) NOT NULL,
	DAY_OF_WEEK_NAME_ABBREVIATION char(3) NOT NULL,
	MONTH_NAME varchar(15) NOT NULL,
	MONTH_NAME_ABBREVIATION char(3) NOT NULL,
	MONTH_FORTNIGHT smallint NOT NULL,
	YEAR_BIMESTER smallint NOT NULL,
	YEAR_QUARTER smallint NOT NULL,
	YEAR_HALF smallint NOT NULL,
	NUMBER_WEEK_MONTH smallint NOT NULL,
	NUMBER_WEEK_YEAR smallint NOT NULL,
	SEASON varchar(15) NOT NULL,
	DATE_FULL varchar(50) NOT NULL,
	EVENT_NAME varchar(50) NULL)

 declare @dateInitial date, @dataFinish date, @date date, 
    @year smallint, @month smallint, @day smallint, 
    @dayOfWeek smallint, @Workday char(1), @Weekend char(1), 
    @holiday char(1), @preHoliday char(1), @posHoliday char(1), 
    @holidayName varchar(30), @dayOfWeekName varchar(15), 
    @dayOfWeekNameAbbreviation char(3), @monthName varchar(15), 
    @monthNameAbbreviation char(3), @yearBimester smallint, @yearQuarter smallint, 
    @numberWeekMonth smallint, @season varchar(15), 
    @dateFull varchar(50)

--enter here the period for which you want to create the data
set @dateInitial = '01/01/2015'
set @dataFinish = '31/12/2020'

while @dateInitial <= @dataFinish
begin
	set @date = @dateInitial
	set @year = year(@date)
	set @month = month(@date)
	set @day = day(@date)
	set @dayOfWeek = datepart(weekday,@date)

	if @dayOfWeek in (1,7) 
		set @Weekend = 1
	else set @Weekend = 0

	/************************* HOLIDAYS ************************
	 *****  Here I considered only the Brazilian holidays *****/

	if (@month = 1 and @day in (1,2)) or (@month = 12 and @day = 31) --confraternização universal
	set @holidayName = 'New Year'
	else 
	if (@month = 4 and @day in (20,21,22)) --tiradentes
	set @holidayName = 'Tiradentes'
	else 
	if (@month = 5 and @day in (1,2))or (@month = 4 and @day = 30) --dia do trabalho
	set @holidayName = 'Labor Day'
	else 
	if (@month = 9 and @day in (6,7,8)) --independência do brasil
	set @holidayName = 'Independence Day'
	else 
	if (@month = 10 and @day in (11,12,13)) --nossa senhora aparecida
	set @holidayName = 'Mother of God'
	else
	if (@month = 11 and @day in (1,2,3)) --finados
	set @holidayName = 'day of the dead'
	else
	if (@month = 11 and @day in (14,15,16)) --proclamação da república
	set @holidayName = 'Republic Proclamation'
	else
	if (@month = 12 and @day in (24,25,26)) --natal
	set @holidayName = 'Christmas'
	else set @holidayName = null

	/* locals or regionals holidays and those that do not have a fixed date
   (carnival, Easter and corpus cristis) should be added here */

	--setting the day before the holiday as TRUE or FALSE
	if (@month = 12 and @day = 31) or --confraternização universal
		(@month = 4 and @day = 20) or --tiradentes
		(@month = 4 and @day = 30) or --dia do trabalho
		(@month = 9 and @day = 6) or --independência do brasil
		(@month = 10 and @day = 11) or --nossa senhora aparecida
		(@month = 11 and @day = 1) or --finados
		(@month = 11 and @day = 14) or --proclamação da república
		(@month = 12 and @day = 24) --natal
		set @preHoliday = 1
	else set @preHoliday = 0

	--setting the day of the holiday as TRUE or FALSE
	if (@month = 1 and @day = 1) or --confraternização universal
		(@month = 4 and @day = 21) or --tiradentes
		(@month = 5 and @day = 1) or --dia do trabalho
		(@month = 9 and @day = 7) or --independência do brasil
		(@month = 10 and @day = 12) or --nossa senhora aparecida
		(@month = 11 and @day = 2) or --finados
		(@month = 11 and @day = 15) or --proclamação da república
		(@month = 12 and @day = 25) --natal
		set @holiday = 1
	else set @holiday = 0

	--setting the day after the holiday as TRUE or FALSE
	if (@month = 1 and @day = 2) or --confraternização universal
		(@month = 4 and @day = 22) or --tiradentes
		(@month = 5 and @day = 2) or --dia do trabalho
		(@month = 9 and @day = 8) or --independência do brasil
		(@month = 10 and @day = 13) or --nossa senhora aparecida
		(@month = 11 and @day = 3) or --finados
		(@month = 11 and @day = 16) or --proclamação da república
		(@month = 12 and @day = 26) --natal
		set @posHoliday = 1
	else set @posHoliday = 0

	--setting the name of month
	set @monthName = case when @month = 1 then 'January'
	                      when @month = 2 then 'February'
	                      when @month = 3 then 'March'
	                      when @month = 4 then 'April'
	                      when @month = 5 then 'May'
	                      when @month = 6 then 'June'
	                      when @month = 7 then 'July'
	                      when @month = 8 then 'August'
	                      when @month = 9 then 'September'
	                      when @month = 10 then 'October'
	                      when @month = 11 then 'November'
	                      else 'December' end

	--setting the abbreviation of the month name
	set @monthNameAbbreviation = case when @month = 1 then 'Jan'
	                                  when @month = 2 then 'Feb'
	                                  when @month = 3 then 'Mar'
	                                  when @month = 4 then 'Apr'
	                                  when @month = 5 then 'MaY'
	                                  when @month = 6 then 'Jun'
	                                  when @month = 7 then 'Jul'
	                                  when @month = 8 then 'Aug'
	                                  when @month = 9 then 'Set'
	                                  when @month = 10 then 'Oct'
	                                  when @month = 11 then 'Nov'
	                                  else 'Dez' end

	--setting workday 
	if @Weekend = 1 or @holiday = 1
	set @Workday = 0
	else set @Workday = 1

	--setting the name of day 
	set @dayOfWeekName = case when @dayOfWeek = 1 then 'Sunday'
	                          when @dayOfWeek = 2 then 'Monday'
	                          when @dayOfWeek = 3 then 'Tuesday'
	                          when @dayOfWeek = 4 then 'Wednesday'
	                          when @dayOfWeek = 5 then 'Thursday'
	                          when @dayOfWeek = 6 then 'Friday'
	                          else 'Saturday' end

	--setting the abbreviation of the day name
	set @dayOfWeekNameAbbreviation = case when @dayOfWeek = 1 then 'Sun'
	                                      when @dayOfWeek = 2 then 'Mon'
	                                      when @dayOfWeek = 3 then 'Tue'
	                                      when @dayOfWeek = 4 then 'Wed'
	                                      when @dayOfWeek = 5 then 'Thu'
	                                      when @dayOfWeek = 6 then 'Fri'
	                                      else 'Sat' end

	--setting the bimester of the year
	set @yearBimester = case when @month in (1,2) then 1
	                         when @month in (3,4) then 2
	                         when @month in (5,6) then 3
	                         when @month in (7,8) then 4
	                         when @month in (9,10) then 5
	                         else 6 end

	--setting the quarter of the year
	set @yearQuarter = case when @month in (1,2,3) then 1
	                        when @month in (4,5,6) then 2
	                        when @month in (7,8,9) then 3
	                        else 4 end

	--setting the number of the week of the month
	set @numberWeekMonth = case when @day < 8 then 1
	                            when @day < 15 then 2
	                            when @day < 22 then 3
	                            when @day < 29 then 4
	                            else 5 end

	--setting the season
	if @date between cast('23/09/'+convert(char(4),@year) as date) and cast('20/12/'+convert(char(4),@year) as date)
		set @season = 'Spring'
	else
	if @date between cast('21/03/'+convert(char(4),@year) as date) and cast('20/06/'+convert(char(4),@year) as date)
		set @season = 'Fall'
	else 
	if @date between cast('21/06/'+convert(char(4),@year) as date) and cast('22/09/'+convert(char(4),@year) as date)
		set @season = 'Winter'
	else -- @date between 21/12 e 20/03
		set @season = 'Summer'

	INSERT INTO DIM_TIME
	SELECT @date
		  , @year
		  , @month
		  , @day
		  , @dayOfWeek
		  , datepart(dayofyear,@date) --DAY_OF_YEAR
		  , case when (@year % 4) = 0 then 1 else 0 end -- LEAP_YEAR
		  , @Workday
		  , @Weekend
		  , @holiday
		  , @preHoliday
		  , @posHoliday
		  , @holidayName
		  , @dayOfWeekName
		  , @dayOfWeekNameAbbreviation
		  , @monthName
		  , @monthNameAbbreviation
		  , case when @day < 16 then 1 else 2 end -- MONTH_FORTNIGHT
		  , @yearBimester
		  , @yearQuarter
		  , case when @month < 7 then 1 else 2 end -- YEAR_HALF
		  , @numberWeekMonth
		  , datepart(wk,@date)--NUMBER_WEEK_YEAR, smallint
		  , @season
		  , lower(@dayOfWeekName + ', ' + @monthName + ' '+ cast(@day as varchar) + ', ' + cast(@year as varchar))
		  , null--EVENT_NAME, varchar(50))

	set @dateInitial = dateadd(day,1,@dateInitial) 
end--while @dateInitial <= @dataFinish