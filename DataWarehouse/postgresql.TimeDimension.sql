-- =====================================================================
-- Author: Fernando Prass | Create date: 03/11/2012
-- Language: PostgreSQL 9.5+
-- Description: Create and populate a time dimension for data warehouses
-- Contact: https://gitlab.com/fernandoprass or https://twitter.com/oFernandoPrass
-- =====================================================================

create table dim_time (
    id_dim_time serial primary key,
    date_small date not null,
    number_year smallint not null,
    month_of_year smallint not null,
    day_of_month smallint not null,
    day_of_week smallint not null,
    day_of_year smallint not null,
    leap_year boolean not null,
    workday boolean not null,
    weekend boolean not null,
    holiday boolean not null,
    pre_holiday boolean not null,
    pos_holiday boolean not null,
    holiday_name varchar(30),
    day_of_week_name varchar(15) not null,
    day_of_week_name_abbreviation char(3) not null,
    month_name varchar(15) not null,
    month_name_abbreviation char(3) not null,
    month_fortnight smallint not null,
    year_bimester smallint not null,
    year_quarter smallint not null,
    year_half smallint not null,
    number_week_month smallint not null,
    number_week_year smallint not null,
    season varchar(15) not null,
    date_full varchar(50) not null,
    event_name varchar(50)
);

insert into dim_time (
    date_small, number_year, month_of_year, day_of_month, day_of_week, 
    day_of_year, leap_year, workday, weekend, holiday, pre_holiday, 
    pos_holiday, holiday_name, day_of_week_name, day_of_week_name_abbreviation, 
    month_name, month_name_abbreviation, month_fortnight, year_bimester, 
    year_quarter, year_half, number_week_month, number_week_year, season, 
    date_full
)
select 
    dt as date_small,
    extract(year from dt) as number_year,
    extract(month from dt) as month_of_year,
    extract(day from dt) as day_of_month,
    extract(dow from dt) + 1 as day_of_week, 
    extract(doy from dt) as day_of_year,
    (extract(year from dt)::int % 4 = 0 and (extract(year from dt)::int % 100 != 0 or extract(year from dt)::int % 400 = 0)) as leap_year,
    false as workday, 
    extract(dow from dt) in (0, 6) as weekend,
    
    -- simplified holiday logic
    case 
        when (m = 1 and d = 1) then true   -- new year
        when (m = 5 and d = 1) then true   -- labor day
        when (m = 12 and d = 25) then true -- christmas
        else false 
    end as holiday,

    -- holidays
    case 
        when (m = 12 and d = 31) or (m = 4 and d = 30) or (m = 12 and d = 24) then true 
        else false 
    end as pre_holiday,
    case 
        when (m = 1 and d = 2) or (m = 5 and d = 2) or (m = 12 and d = 26) then true 
        else false 
    end as pos_holiday,
    case 
        when (m = 1 and d = 1) then 'new year'
        when (m = 5 and d = 1) then 'labor day'
        when (m = 12 and d = 25) then 'christmas'
        else null 
    end as holiday_name,

    to_char(dt, 'day') as day_of_week_name,
    to_char(dt, 'dy') as day_of_week_name_abbreviation,
    to_char(dt, 'month') as month_name,
    to_char(dt, 'mon') as month_name_abbreviation,
    case when d < 16 then 1 else 2 end as month_fortnight,
    ceil(m / 2.0) as year_bimester,
    extract(quarter from dt) as year_quarter,
    case when m < 7 then 1 else 2 end as year_half,
    ceil(d / 7.0) as number_week_month,
    extract(week from dt) as number_week_year,

    case 
        when dt >= (y || '-09-23')::date and dt <= (y || '-12-20')::date then 'spring'
        when dt >= (y || '-03-21')::date and dt <= (y || '-06-20')::date then 'fall'
        when dt >= (y || '-06-21')::date and dt <= (y || '-09-22')::date then 'winter'
        else 'summer'
    end as season,

    lower(to_char(dt, 'day, month dd, yyyy')) as date_full
from (
    select 
        dt::date as dt,
        extract(month from dt) as m,
        extract(day from dt) as d,
        extract(year from dt) as y
    from generate_series('2015-01-01'::timestamp, '2020-12-31'::timestamp, '1 day') as dt
) sub;

-- finalize workday calculation
update dim_time set workday = not (weekend or holiday);