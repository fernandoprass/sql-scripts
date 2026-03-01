-- =====================================================================
-- Author: Fernando Prass | Create date: 01/03/2026
-- Database: PostgreSQL 10+
-- Description: Health Monitoring for Table and Index 
-- Contact: https://github.com/fernandoprass or https://twitter.com/oFernandoPrass
-- =====================================================================

/*
================================================================================
SCRIPT SUMMARY & USAGE INSTRUCTIONS
================================================================================
PART I   - TABLE HEALTH MONITOR: Provides a high-level overview of row counts, 
           physical disk usage, and bloat (dead tuples) for user tables.

PART II  - INDEX DETAILED AUDIT: Lists all user indexes with their type (B-tree, 
           GIN, etc.), physical size, and actual usage frequency.

PART III - UNUSED INDEX DETECTOR: Specifically targets "zombie" indexes that 
           consume disk space and slow down writes without being used by queries.

PART IV  - ACTIONABLE DASHBOARD: A filtered "To-Do" list showing only objects 
           that currently exceed 20% bloat or show critical inefficiency.

WARNING: This script is for monitoring only. Before acting on the results:
- Run 'VACUUM ANALYZE' to refresh statistics before trusting bloat numbers.
- Verify an index is truly unused over a full business cycle before dropping it.
- Use 'VACUUM FULL' with caution as it requires an exclusive table lock.
================================================================================
*/

/*
================================================================================
PART I. TABLE MONITORING SCRIPT (User-Created Tables Only)
================================================================================
DESCRIPTION: 
Provides a high-level overview of table health, including physical size on disk, 
row counts, and "bloat" indicators (dead tuples).

COLUMNS EXPLAINED:
- total_size_mb: Includes table data, indexes, and TOAST (large object) data.
- table_size_mb: Only the raw data inside the table.
- index_size_mb: Only the size of attached indexes.
- live_rows: Estimated number of active rows.
- dead_rows: Rows that are deleted/obsolete but not yet vacuumed (indicates bloat).
- last_vacuum: The last time maintenance was performed on this table.


TIPS:
dead_rows & bloat_percentage: If a table has a high number of dead rows (e.g., > 20%), 
it means your autovacuum settings might be too slow. Dead rows occupy space and slow down sequential scans.

total_size_mb vs table_only_mb: If index size is significantly larger than your table size, 
you might have redundant or unused indexes that are slowing down INSERT and UPDATE operations.

last_autovacuum: This tells you if the background maintenance is actually visiting this table. 
If this field is NULL for a high-write table, you have a configuration problem.

Quick Maintenance Commands
If you find a table with high bloat from the script above, you can run these manually to fix it:

ANALYZE table_name;: Updates statistics so the query planner makes better decisions.

VACUUM table_name;: Reclaims space from dead rows.

REINDEX TABLE table_name;: Rebuilds indexes from scratch (useful if index_only_mb is huge).
================================================================================
*/

SELECT 
    schemaname AS schema_name,
    relname AS table_name,
    -- 1. LINE COUNTS
    n_live_tup AS live_rows,  -- Estimated number of live rows
    n_dead_tup AS dead_lines, -- Rows deleted but not yet reclaimed
    
    -- 2. SIZE IN MB (Human Readable)
    pg_size_pretty(pg_total_relation_size(relid)) AS total_size_pretty,               -- Total size (data + indexes + TOAST)
    ROUND(pg_total_relation_size(relid) / (1024 * 1024)::numeric, 2) AS total_size_mb, -- Total size in MB
    ROUND(pg_relation_size(relid) / (1024 * 1024)::numeric, 2) AS data_only_mb,        -- Size of just the table data
    ROUND((pg_total_relation_size(relid) - pg_relation_size(relid)) / (1024 * 1024)::numeric, 2) AS index_size_mb,-- Size of indexes (total - data)

    -- 3. HEALTH RATIOS
    CASE 
        WHEN n_live_tup > 0 THEN ROUND((n_dead_tup::numeric / n_live_tup::numeric) * 100, 2)
        ELSE 0 
    END AS bloat_percentage, -- Percentage of dead rows compared to live rows

    -- 4. ACTIVITY & MAINTENANCE
    seq_scan AS full_table_scans, -- High numbers here suggest missing indexes
    idx_scan AS index_scans,      -- High numbers here suggest good index usage
    last_autovacuum,
    last_autoanalyze
FROM pg_stat_user_tables
-- Filter out system tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY pg_total_relation_size(relid) DESC;

/* ================================================================================
PART III. USER INDEX DETAILED MONITOR
================================================================================
DESCRIPTION:
Provides a full inventory of user-created indexes with size and usage metrics.

COLUMNS EXPLAINED:
- index_type: Usually 'btree' (default), but can be 'gin', 'gist', or 'hash'.
- index_size_mb: The physical space this index occupies on disk.
- usage_count: How many times the query planner actually used this index.
- table_scans_ratio: If usage_count is low but the table has many sequential scans,
  this index might be built on the wrong column.
================================================================================
*/

SELECT
    i.schemaname AS schema_name,
    i.relname AS table_name,
    i.indexrelname AS index_name,
    idx.indisunique AS is_unique,
    idx.indisprimary AS is_primary,
    am.amname AS index_type,
    
    -- Size Analysis
    pg_size_pretty(pg_relation_size(i.indexrelid)) AS size_pretty,
    ROUND(pg_relation_size(i.indexrelid) / (1024 * 1024)::numeric, 2) AS size_mb,
    
    -- Usage Analysis
    i.idx_scan AS usage_count,
    i.idx_tup_read AS tuples_read,
    i.idx_tup_fetch AS tuples_fetched,
    
    -- Definition
    pg_get_indexdef(i.indexrelid) AS index_definition

FROM pg_stat_user_indexes i
JOIN pg_index idx ON i.indexrelid = idx.indexrelid
JOIN pg_class c ON i.indexrelid = c.oid
JOIN pg_am am ON c.relam = am.oid
WHERE i.schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY pg_relation_size(i.indexrelid) DESC;


/* ================================================================================
PART III. UNUSED INDEX DETECTOR
================================================================================
Finds indexes that have 0 scans. These are candidates for deletion to save 
disk space and speed up write operations.
================================================================================
*/

SELECT 
    schemaname,
    relname AS table_name,
    indexrelname AS index_name,
    pg_size_pretty(pg_relation_size(i.indexrelid)) AS index_size,
    idx_scan AS times_used
FROM pg_stat_user_indexes ui
JOIN pg_index i ON ui.indexrelid = i.indexrelid
WHERE ui.idx_scan = 0 
  AND i.indisunique IS FALSE -- Don't drop unique constraints!
  AND schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY pg_relation_size(i.indexrelid) DESC;


/* ================================================================================
PART IV. DASHBOARD: TABLES REQUIRING MAINTENANCE
================================================================================
FILTERS:
- High Bloat: Dead rows > 20% of total rows
- Unused Indexes: Tables with at least 1 index that has 0 scans
- Potential Missing Indexes: Tables with more Full Scans than Index Scans

**************** Action Plan for the Results ****************
If a table appears in this list, follow these steps based on the column that triggered the alert:

If bloat_pct is high: Run VACUUM ANALYZE table_name;. If the table is massive and the space isn't 
being reclaimed to the OS, you may need VACUUM FULL, but be careful: this locks the table.

If unused_indexes > 0: Run the "Unused Index Detector" script from our previous step to find the 
specific names of the indexes, then DROP INDEX index_name; (after verifying they aren't for yearly reports).

If full_scans is high: Your queries are ignoring indexes or the indexes don't exist. Review your 
SELECT statements' WHERE clauses and add appropriate indexes.
================================================================================
*/

SELECT * FROM (
    SELECT 
        t.schemaname AS schema,
        t.relname AS table_name,
        
        -- Capacity
        t.n_live_tup AS total_lines,
        pg_size_pretty(pg_total_relation_size(t.relid)) AS total_size,
        
        -- Bloat Alert (> 20%)
        t.n_dead_tup AS dead_lines,
        CASE 
            WHEN t.n_live_tup > 0 
            THEN ROUND((t.n_dead_tup::numeric / t.n_live_tup::numeric) * 100, 2) 
            ELSE 0 
        END AS bloat_pct,

        -- Index Waste Alert
        (SELECT count(*) FROM pg_stat_user_indexes ui 
         WHERE ui.relid = t.relid AND ui.idx_scan = 0 
         AND (SELECT indisunique FROM pg_index WHERE indexrelid = ui.indexrelid) IS FALSE
        ) AS unused_indexes,

        -- Efficiency Alert (Full Scans vs Index Scans)
        t.seq_scan AS full_scans,
        t.idx_scan AS index_scans,
        
        -- Maintenance Recency
        COALESCE(to_char(GREATEST(t.last_autovacuum, t.last_vacuum), 'YYYY-MM-DD'), 'Never') AS last_vacuum_date
    FROM pg_stat_user_tables t
    WHERE t.schemaname NOT IN ('pg_catalog', 'information_schema')
) AS health_metrics
WHERE 
    bloat_pct > 20           -- Filter: High Bloat
    OR unused_indexes > 0    -- Filter: Wasted space
    OR (full_scans > 100 AND full_scans > index_scans) -- Filter: Missing Index pattern
ORDER BY bloat_pct DESC, unused_indexes DESC;