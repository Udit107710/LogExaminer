-- Top N Log Analytics Queries
-- This file contains SQL queries to create aggregated views of log data

-- Create top errors by count (overwrite if exists)
CREATE OR REPLACE TABLE iceberg.analytics.top_errors_by_count
USING ICEBERG
AS
SELECT 
    level,
    source,
    message,
    COUNT(*) as error_count,
    MAX(timestamp) as latest_occurrence,
    MIN(timestamp) as first_occurrence,
    current_timestamp() as aggregation_timestamp
FROM iceberg.analytics.logs 
WHERE level IN ('ERROR', 'WARN')
GROUP BY level, source, message
ORDER BY error_count DESC
LIMIT 100;

-- Create daily log summary (overwrite if exists) 
CREATE OR REPLACE TABLE iceberg.analytics.daily_log_summary
USING ICEBERG
AS
SELECT 
    date_partition,
    level,
    COUNT(*) as log_count,
    COUNT(DISTINCT source) as unique_sources,
    COUNT(DISTINCT user_id) as unique_users,
    current_timestamp() as aggregation_timestamp
FROM iceberg.analytics.logs 
GROUP BY date_partition, level
ORDER BY date_partition DESC, level;

-- Create hourly error trends
CREATE OR REPLACE TABLE iceberg.analytics.hourly_error_trends
USING ICEBERG
AS
SELECT 
    date_format(timestamp, 'yyyy-MM-dd HH:00:00') as hour,
    level,
    COUNT(*) as error_count,
    COUNT(DISTINCT source) as unique_sources,
    current_timestamp() as aggregation_timestamp
FROM iceberg.analytics.logs 
WHERE level IN ('ERROR', 'WARN', 'FATAL')
GROUP BY date_format(timestamp, 'yyyy-MM-dd HH:00:00'), level
ORDER BY hour DESC, level;

-- Create source activity summary
CREATE OR REPLACE TABLE iceberg.analytics.source_activity_summary
USING ICEBERG
AS
SELECT 
    source,
    COUNT(*) as total_logs,
    SUM(CASE WHEN level = 'ERROR' THEN 1 ELSE 0 END) as error_count,
    SUM(CASE WHEN level = 'WARN' THEN 1 ELSE 0 END) as warn_count,
    SUM(CASE WHEN level = 'INFO' THEN 1 ELSE 0 END) as info_count,
    SUM(CASE WHEN level = 'DEBUG' THEN 1 ELSE 0 END) as debug_count,
    MAX(timestamp) as latest_log,
    MIN(timestamp) as first_log,
    current_timestamp() as aggregation_timestamp
FROM iceberg.analytics.logs 
GROUP BY source
ORDER BY total_logs DESC;

-- Create user activity summary for user behavior analysis
CREATE OR REPLACE TABLE iceberg.analytics.user_activity_summary
USING ICEBERG
AS
SELECT 
    user_id,
    COUNT(*) as total_activity,
    COUNT(DISTINCT session_id) as unique_sessions,
    COUNT(DISTINCT ip_address) as unique_ip_addresses,
    SUM(CASE WHEN level = 'ERROR' THEN 1 ELSE 0 END) as error_count,
    MAX(timestamp) as latest_activity,
    MIN(timestamp) as first_activity,
    current_timestamp() as aggregation_timestamp
FROM iceberg.analytics.logs 
WHERE user_id IS NOT NULL
GROUP BY user_id
ORDER BY total_activity DESC
LIMIT 1000;

-- Create IP address analysis for security insights
CREATE OR REPLACE TABLE iceberg.analytics.ip_address_analysis
USING ICEBERG
AS
SELECT 
    ip_address,
    COUNT(*) as total_requests,
    COUNT(DISTINCT user_id) as unique_users,
    COUNT(DISTINCT session_id) as unique_sessions,
    SUM(CASE WHEN level = 'ERROR' THEN 1 ELSE 0 END) as error_count,
    MAX(timestamp) as latest_request,
    MIN(timestamp) as first_request,
    current_timestamp() as aggregation_timestamp
FROM iceberg.analytics.logs 
WHERE ip_address IS NOT NULL
GROUP BY ip_address
ORDER BY total_requests DESC
LIMIT 500;
