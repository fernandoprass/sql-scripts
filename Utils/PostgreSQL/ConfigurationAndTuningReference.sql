-- =====================================================================
-- Author: Fernando Prass | Create date: 01/03/2026
-- Database: PostgreSQL 10+
-- Description: Most common configuration and tuning settings
-- Contact: https://github.com/fernandoprass or https://twitter.com/oFernandoPrass
-- =====================================================================

/*
================================================================================
SCRIPT SUMMARY & USAGE INSTRUCTIONS
================================================================================
PART I   - CONFIGURATION ANALYSIS: Calculates recommended settings based on your
           server's RAM and disk type to provide a baseline for optimization.

PART II  - SYSTEM PERMANENT UPDATES: Applies optimized settings to the server's 
           persistent configuration files using the ALTER SYSTEM command.

PART III - SOURCE TRACEABILITY: Audits which specific configuration file (manual 
           vs auto) is currently controlling your database parameters.

PART IV  - CPU & WORKER LOGIC: Provides insights into how to configure worker 
           processes and parallelism settings based on your server's CPU cores.

******************************** R E A D M E *********************************
WARNING: DO NOT run the entire script at once. You must execute each part 
separately. Specifically, the 'ALTER SYSTEM' commands in Part II must be 
executed one-by-one outside of any transaction block to avoid execution errors.
*******************************************************************************
================================================================================
*/

/*
================================================================================
PART I. TECHNICAL SUMMARY OF KEY PARAMETERS:
================================================================================

1. SHARED_BUFFERS: 
   Defines the amount of memory PostgreSQL uses for shared memory buffers.
   - Logic: 25% of RAM is the "sweet spot." Setting it higher can actually hurt 
     performance due to how the Operating System also caches data.

2. EFFECTIVE_CACHE_SIZE: 
   An estimate of how much memory is available for disk caching by the OS and 
   the DB. It doesn't "reserve" memory; it just helps the optimizer decide if 
   an index will likely fit in RAM.
   - Logic: Setting this to 75% helps the planner prefer Index Scans over Seq Scans.

3. WORK_MEM: 
   The memory used for internal sort operations and hash tables (per operation).
   - Logic: If complex queries swap to disk (check logs for "external sort"), 
     increase this. Note: total memory used can be (work_mem * active_connections).

4. MAINTENANCE_WORK_MEM: 
   Memory used for VACUUM, CREATE INDEX, and ALTER TABLE.
   - Logic: Larger values speed up index creation and vacuuming. 2GB is usually 
     the practical ceiling for this setting.

5. RANDOM_PAGE_COST: 
   Tells the optimizer the cost of non-sequential disk access.
   - Logic: Default is 4.0 (HDD). Modern SSDs are much faster, so 1.1 reduces 
     the "penalty" for random access, making the optimizer use indexes more often.

6. AUTOVACUUM_MAX_WORKERS: 
   Number of background worker processes for autovacuum.
   - Logic: More workers prevent table bloat on high-write systems.

7. CHECKPOINT_TIMEOUT & MAX_WAL_SIZE: 
   Controls how often the DB flushes data to disk. 
   - Logic: Increasing these reduces I/O spikes but increases recovery time if 
     the server crashes.
================================================================================
*/

-- 1. DEFINE YOUR INPUTS
set my.total_ram_gb = '16'; -- Edit your RAM here
set my.is_ssd = 'true';      -- Set to 'false' for HDD

-- 2. RUN ANALYSIS (Dynamic Select)
with settings_input as (
    select 
        current_setting('my.total_ram_gb')::numeric as ram_gb,
        current_setting('my.is_ssd')::boolean as is_ssd
)
select 
    name as parameter,
    setting || ' ' || coalesce(unit, '') as current_value,
    case 
        when name = 'shared_buffers' then (ram_gb * 1024 / 4)::int || 'MB'
        when name = 'effective_cache_size' then (ram_gb * 1024 * 3 / 4)::int || 'MB'
        when name = 'maintenance_work_mem' then least(ram_gb * 1024 / 20, 2048)::int || 'MB'
        when name = 'work_mem' then '64MB'
        when name = 'random_page_cost' then (case when is_ssd then '1.1' else '4.0' end)
        when name = 'max_connections' then '100-500'
        when name = 'autovacuum_max_workers' then '3-5'
        else 'check documentation'
    end as suggested_value,
    short_desc as description
from pg_settings, settings_input
where name in (
    'shared_buffers',
    'work_mem',
    'maintenance_work_mem',
    'effective_cache_size',
    'random_page_cost',
    'max_connections',
    'autovacuum_max_workers',
    'max_wal_size',
    'checkpoint_timeout'
)
order by name;

/*
================================================================================
PART II. POSTGRESQL DYNAMIC CONFIGURATION SUMMARY
================================================================================
1. AUTOMATION: This script uses a PL/pgSQL 'DO' block to calculate memory 
   settings based on a RAM variable. Since 'ALTER SYSTEM' doesn't accept 
   variables, 'EXECUTE' is used to run the commands as dynamic strings.

2. STORAGE: 'ALTER SYSTEM' writes settings to 'postgresql.auto.conf'. 
   This file has higher priority than the manual 'postgresql.conf', 
   meaning these values will override any manual edits.

3. ACTIVATION: 
   - 'RELOAD' (pg_reload_conf): Applies most changes immediately.
   - 'RESTART' (OS level): Required for 'shared_buffers' and 'max_connections'.

PROBLEM: If you see "ALTER SYSTEM cannot run inside a transaction block," it 
is because your SQL editor is wrapping these commands in a BEGIN/COMMIT block.

SOLUTION: 
- These commands must be executed individually (one by one).
- Ensure "Auto-commit" is ENABLED in your SQL editor.
- Do not wrap these commands inside a 'DO $$...$$' block or a Function.
================================================================================
*/

-- 1. APPLY PERMANENT CHANGES 
-- Replace values below based on the suggested_value output above.
-- AGAIN: run one by one, outside of any transaction block

alter system set shared_buffers = '4GB';        -- Requires RESTART
alter system set effective_cache_size = '12GB'; -- Requires RELOAD
alter system set work_mem = '64MB';             -- Requires RELOAD
alter system set random_page_cost = 1.1;        -- Requires RELOAD

-- 2. RELOAD CONFIGURATION (Run after alter system commands)
select pg_reload_conf();


/*
================================================================================
PART III. POSTGRESQL CONFIGURATION FILE HIERARCHY NOTE:
================================================================================
PostgreSQL manages configuration through two primary files:

1. postgresql.conf: 
   The main configuration file. It is intended for manual edits and contains 
   initial setup and documentation/comments.

2. postgresql.auto.conf: 
   Created and managed by the 'ALTER SYSTEM' command. This file is located 
   in the database data directory.

PRECEDENCE RULE: 
PostgreSQL reads postgresql.auto.conf AFTER postgresql.conf. Therefore, 
any setting in '.auto.conf' (set via SQL) OVERRIDES the manual '.conf' file.

BEST PRACTICE:
- Use 'ALTER SYSTEM' for changes made via scripts or remote management.
- Use 'ALTER SYSTEM RESET <parameter>' to remove a setting from .auto.conf 
  and revert back to the value defined in the manual postgresql.conf.
- Always check 'pg_settings.sourcefile' to verify which file is currently 
  controlling a specific parameter.

HOW TO KNOW CONFIGURARION FILE IS IN USE:
To check which configuration file is driving each setting, query the pg_settings 
view and look at the sourcefile column (command below).

If sourcefile is null, it is using the default compiled-in value.
If sourcefile ends in postgresql.conf, it's your manual setting.
If sourcefile ends in postgresql.auto.conf, it's a value set via ALTER SYSTEM.
================================================================================
*/

select 
    name, 
    setting, 
    sourcefile, 
    sourceline,
    source
from pg_settings 
where name in (
    'shared_buffers',
    'work_mem',
    'maintenance_work_mem',
    'effective_cache_size',
    'random_page_cost',
    'max_connections'
);

/*
================================================================================
PART IV. CPU & WORKER LOGIC:
================================================================================
- max_worker_processes: The total limit of background processes. Usually set 
  to the number of CPU cores.
- autovacuum_max_workers: Default is 3. On high-write systems with many 
  databases/tables, increase this to 5 or 6 to prevent "vacuum starvation."
- max_parallel_workers_per_gather: Controls how many CPUs a single query can 
  use. Set this to ~25% of your total cores.
================================================================================
*/

select 
    name, 
    setting, 
    short_desc 
from pg_settings 
where name in (
    'max_worker_processes',
    'max_parallel_workers',
    'max_parallel_workers_per_gather',
    'autovacuum_max_workers'
);