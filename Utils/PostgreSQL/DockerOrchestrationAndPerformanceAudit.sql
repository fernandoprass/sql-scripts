-- =====================================================================
-- Author: Fernando Prass | Create date: 01/03/2026
-- Database: PostgreSQL 10+
-- Description: PostgreSQL Docker Orchestration & Performance Audit
-- Contact: https://github.com/fernandoprass or https://twitter.com/oFernandoPrass
-- =====================================================================

/*
================================================================================
SCRIPT SUMMARY & USAGE INSTRUCTIONS
================================================================================
COMPATIBILITY: Designed for PostgreSQL 10+ running in Docker Environments.

PART I   - DOCKER ORCHESTRATION: YAML configuration for a tuned Postgres 17 
           container. Defines critical SHM (Shared Memory) limits and hardware 
           constraints (8GB RAM / 4 CPUs) to ensure stability.
PART II  - MEMORY WORKLOAD MONITOR: SQL query to detect active queries using 
           'work_mem'. Crucial for preventing OOM (Out of Memory) kills by 
           the Docker daemon.
PART III - I/O HEALTH CHECK: Monitors 'temp_files' and disk spilling. Used to 
           determine if your Docker container needs more RAM or if your 
           internal work_mem setting is too low for your dataset.

WARNING: RUN PART BY PART.
1. The YAML block must be saved as 'docker-compose.yml' and run via terminal.
2. The 'docker stats' command must be run in your OS command prompt/bash.
3. The SQL queries in Parts II and III should be run inside your SQL editor.
================================================================================
*/

/*
================================================================================
PART I. DOCKER-SPECIFIC CONSIDERATIONS (YML BLOCK)
================================================================================
1. SHM_SIZE: Docker's default shared memory (/dev/shm) is 64MB. If your 
   'shared_buffers' is larger than this, Postgres will fail to start. 
   Always set 'shm_size' in your docker-compose or --shm-size in 'docker run'.

2. MEMORY LIMITS: Ensure the Docker '--memory' limit is at least 20-30% 
   higher than 'shared_buffers' to allow room for the OS cache and 'work_mem'.

3. PERSISTENCE: Never store data inside the container layer. Use Docker 
   Volumes for '/var/lib/postgresql/data' to ensure performance and safety.

4. IOPS: If running on Docker Desktop (Windows/Mac), disk I/O is much slower 
   than native Linux. Set 'synchronous_commit = off' in development environments 
   to regain speed (but do NOT do this in production without a UPS).
================================================================================
*/

services:
  postgres_db:
    image: postgres:17-alpine
    container_name: pg_production
    restart: always
    environment:
      POSTGRES_PASSWORD: your_secure_password
      POSTGRES_DB: my_database
    shm_size: '2gb' # IMPORTANT: Must be at least as large as shared_buffers
    deploy:
      resources:
        limits:
          memory: 8gb   # Physical RAM limit for the container
          cpus: '4.0'   # CPU core limit
    volumes:
      - pgdata:/var/lib/postgresql/data
    # Passing tuning parameters directly to the entrypoint
    command: >
      postgres 
      -c shared_buffers=2GB 
      -c effective_cache_size=6GB 
      -c work_mem=64MB 
      -c maintenance_work_mem=512MB 
      -c random_page_cost=1.1
      -c max_connections=200

volumes:
  pgdata:


--Run the Bash command below in your terminal to see if your container is approaching its memory limit.

docker stats pg_production

/*
================================================================================
PART II. ACTIVE WORK_MEM MONITORING:
================================================================================
This query identifies if current queries are consuming significant memory.
If 'Total Est Work Mem' exceeds your container's free RAM, Docker may kill 
the process (OOM Killer).
================================================================================
*/
select 
    pid, 
    state, 
    query, 
    (select setting || ' ' || unit from pg_settings where name = 'work_mem') as work_mem_per_op,
    now() - query_start as duration
from pg_stat_activity 
where state = 'active' 
  and pid <> pg_backend_pid();

/*
================================================================================
PART III. PERFORMANCE & HEALTH CHECKLIST:
================================================================================
- Check for Disk Spilling: If 'temp_files' in pg_stat_database is high, 
  increase 'work_mem'.
- Monitor Docker Stats: If container MEM % is > 90%, reduce 'shared_buffers' 
  or increase container memory limit.
- Connection Bloat: If 'max_connections' is consistently reached, implement 
  PgBouncer instead of simply increasing the number (each connection adds overhead).
================================================================================
*/

select 
    datname, 
    temp_files, 
    temp_bytes / 1024 / 1024 as temp_mb 
from pg_stat_database;