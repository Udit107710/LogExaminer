-- Top N Log Analytics Queries
-- This file contains SQL queries to create aggregated views of log data

-- Create top errors by count (overwrite if exists)
CREATE OR REPLACE TABLE iceberg.analytics.top_errors_by_count
USING ICEBERG
AS
SELECT 
    level,
    logger,
    message,
    COUNT(*) as error_count,
    MAX(timestamp) as latest_occurrence,
    MIN(timestamp) as first_occurrence,
    current_timestamp() as aggregation_timestamp
FROM iceberg.analytics.logs 
WHERE level IN ('ERROR', 'WARN')
GROUP BY level, logger, message
ORDER BY error_count DESC
LIMIT 100;

-- Create daily log summary (overwrite if exists) 
CREATE OR REPLACE TABLE iceberg.analytics.daily_log_summary
USING ICEBERG
AS
SELECT 
    partition_date,
    level,
    COUNT(*) as log_count,
    COUNT(DISTINCT logger) as unique_loggers,
    current_timestamp() as aggregation_timestamp
FROM iceberg.analytics.logs 
GROUP BY partition_date, level
ORDER BY partition_date DESC, level;

-- Create hourly error trends
CREATE OR REPLACE TABLE iceberg.analytics.hourly_error_trends
USING ICEBERG
AS
SELECT 
    date_format(timestamp, 'yyyy-MM-dd HH:00:00') as hour,
    level,
    COUNT(*) as error_count,
    COUNT(DISTINCT logger) as unique_loggers,
    current_timestamp() as aggregation_timestamp
FROM iceberg.analytics.logs 
WHERE level IN ('ERROR', 'WARN', 'FATAL')
GROUP BY date_format(timestamp, 'yyyy-MM-dd HH:00:00'), level
ORDER BY hour DESC, level;

-- Create logger activity summary
CREATE OR REPLACE TABLE iceberg.analytics.logger_activity_summary
USING ICEBERG
AS
SELECT 
    logger,
    COUNT(*) as total_logs,
    SUM(CASE WHEN level = 'ERROR' THEN 1 ELSE 0 END) as error_count,
    SUM(CASE WHEN level = 'WARN' THEN 1 ELSE 0 END) as warn_count,
    SUM(CASE WHEN level = 'INFO' THEN 1 ELSE 0 END) as info_count,
    MAX(timestamp) as latest_log,
    MIN(timestamp) as first_log,
    current_timestamp() as aggregation_timestamp
FROM iceberg.analytics.logs 
GROUP BY logger
ORDER BY total_logs DESC;

-- Create exception summary for debugging
CREATE OR REPLACE TABLE iceberg.analytics.exception_summary
USING ICEBERG
AS
SELECT 
    COALESCE(exception_class, 'No Exception') as exception_class,
    COALESCE(exception_message, 'No Message') as exception_type,
    COUNT(*) as occurrence_count,
    MAX(timestamp) as latest_occurrence,
    COLLECT_LIST(DISTINCT logger) as affected_loggers,
    current_timestamp() as aggregation_timestamp
FROM iceberg.analytics.logs 
WHERE level = 'ERROR'
GROUP BY exception_class, exception_message
ORDER BY occurrence_count DESC
LIMIT 50;
