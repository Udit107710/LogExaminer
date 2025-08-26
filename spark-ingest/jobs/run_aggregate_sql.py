#!/usr/bin/env python3
"""
Spark job to run SQL aggregation queries on Iceberg tables via Hive Metastore.
This job executes SQL files and writes results to Iceberg tables for analytics.
"""

import argparse
import sys
import os
from pyspark.sql import SparkSession
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def create_spark_session(warehouse_path, hms_uri):
    """Create Spark session with Iceberg and Hive support."""
    return SparkSession.builder \
        .appName("RunAggregateSQL") \
        .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions") \
        .config("spark.sql.catalog.iceberg", "org.apache.iceberg.spark.SparkCatalog") \
        .config("spark.sql.catalog.iceberg.catalog-impl", "org.apache.iceberg.hive.HiveCatalog") \
        .config("spark.sql.catalog.iceberg.uri", hms_uri) \
        .config("spark.sql.catalog.iceberg.warehouse", warehouse_path) \
        .config("spark.hadoop.fs.s3a.aws.credentials.provider", "com.amazonaws.auth.WebIdentityTokenCredentialsProvider") \
        .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem") \
        .config("spark.hadoop.fs.s3a.path.style.access", "false") \
        .config("spark.serializer", "org.apache.spark.serializer.KryoSerializer") \
        .getOrCreate()

def read_sql_file(sql_file_path):
    """Read SQL file content."""
    try:
        with open(sql_file_path, 'r') as file:
            sql_content = file.read().strip()
        
        if not sql_content:
            raise ValueError(f"SQL file {sql_file_path} is empty")
            
        logger.info(f"Successfully read SQL file: {sql_file_path}")
        return sql_content
    except FileNotFoundError:
        logger.error(f"SQL file not found: {sql_file_path}")
        raise
    except Exception as e:
        logger.error(f"Error reading SQL file {sql_file_path}: {e}")
        raise

def execute_sql_statements(spark, sql_content):
    """Execute SQL statements, handling both DDL and DML."""
    # Split SQL content by semicolons, but be careful with complex queries
    statements = [stmt.strip() for stmt in sql_content.split(';') if stmt.strip()]
    
    results = []
    for i, statement in enumerate(statements):
        try:
            logger.info(f"Executing SQL statement {i+1}/{len(statements)}")
            logger.info(f"SQL: {statement[:200]}..." if len(statement) > 200 else f"SQL: {statement}")
            
            # Execute the SQL statement
            result = spark.sql(statement)
            
            # Check if this is a query that returns results
            if statement.strip().upper().startswith(('SELECT', 'SHOW', 'DESCRIBE', 'WITH')):
                row_count = result.count()
                logger.info(f"Statement {i+1} executed successfully, returned {row_count} rows")
                results.append({
                    'statement_index': i+1,
                    'statement': statement[:100] + '...' if len(statement) > 100 else statement,
                    'row_count': row_count,
                    'success': True
                })
            else:
                # DDL/DML statements
                logger.info(f"Statement {i+1} executed successfully (DDL/DML)")
                results.append({
                    'statement_index': i+1,
                    'statement': statement[:100] + '...' if len(statement) > 100 else statement,
                    'row_count': 0,
                    'success': True
                })
                
        except Exception as e:
            logger.error(f"Error executing statement {i+1}: {e}")
            logger.error(f"Failed statement: {statement}")
            results.append({
                'statement_index': i+1,
                'statement': statement[:100] + '...' if len(statement) > 100 else statement,
                'row_count': 0,
                'success': False,
                'error': str(e)
            })
            # Continue with other statements rather than failing completely
    
    return results

def create_analytics_database_if_not_exists(spark):
    """Create analytics database if it doesn't exist."""
    try:
        spark.sql("CREATE DATABASE IF NOT EXISTS iceberg.analytics")
        logger.info("Analytics database created or already exists")
    except Exception as e:
        logger.error(f"Failed to create analytics database: {e}")
        raise

def create_sample_aggregation_if_needed(spark):
    """Create sample aggregation table if source data exists."""
    try:
        # Check if the logs table exists and has data
        tables_df = spark.sql("SHOW TABLES IN iceberg.analytics")
        table_names = [row['tableName'] for row in tables_df.collect()]
        
        if 'logs' not in table_names:
            logger.warning("Source logs table not found, skipping aggregation")
            return
        
        # Check if logs table has data
        log_count = spark.sql("SELECT COUNT(*) as count FROM iceberg.analytics.logs").collect()[0]['count']
        if log_count == 0:
            logger.warning("No data in logs table, skipping aggregation")
            return
        
        logger.info(f"Found {log_count} records in logs table, creating aggregations")
        
        # Create top errors by count
        spark.sql("""
            CREATE TABLE IF NOT EXISTS iceberg.analytics.top_errors_by_count
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
            LIMIT 100
        """)
        
        # Create daily log summary
        spark.sql("""
            CREATE TABLE IF NOT EXISTS iceberg.analytics.daily_log_summary
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
            ORDER BY partition_date DESC, level
        """)
        
        logger.info("Sample aggregation tables created successfully")
        
    except Exception as e:
        logger.error(f"Error creating sample aggregations: {e}")
        # Don't fail the job, just log the error
        pass

def main():
    parser = argparse.ArgumentParser(description="Run SQL aggregation queries")
    parser.add_argument("--sql-file", required=True, help="Path to SQL file to execute")
    parser.add_argument("--warehouse", required=True, help="Iceberg warehouse location")
    parser.add_argument("--hms-uri", required=True, help="Hive Metastore URI")
    
    args = parser.parse_args()
    
    logger.info("Starting SQL aggregation job")
    logger.info(f"SQL file: {args.sql_file}")
    logger.info(f"Warehouse: {args.warehouse}")
    logger.info(f"HMS URI: {args.hms_uri}")
    
    spark = None
    try:
        # Create Spark session
        spark = create_spark_session(args.warehouse, args.hms_uri)
        logger.info("Spark session created successfully")
        
        # Ensure analytics database exists
        create_analytics_database_if_not_exists(spark)
        
        # Check if SQL file exists, if not create sample aggregations
        if not os.path.exists(args.sql_file):
            logger.warning(f"SQL file {args.sql_file} not found, creating sample aggregations")
            create_sample_aggregation_if_needed(spark)
            logger.info("Job completed with sample aggregations")
            return
        
        # Read and execute SQL file
        sql_content = read_sql_file(args.sql_file)
        
        # Execute SQL statements
        results = execute_sql_statements(spark, sql_content)
        
        # Log results summary
        successful_statements = len([r for r in results if r['success']])
        total_statements = len(results)
        
        logger.info(f"Job completed: {successful_statements}/{total_statements} statements executed successfully")
        
        # Log details of failed statements
        failed_results = [r for r in results if not r['success']]
        if failed_results:
            logger.warning(f"{len(failed_results)} statements failed:")
            for result in failed_results:
                logger.warning(f"  Statement {result['statement_index']}: {result['statement']}")
                logger.warning(f"    Error: {result.get('error', 'Unknown error')}")
        
        # If more than half the statements failed, exit with error
        if len(failed_results) > len(results) / 2:
            logger.error("More than half the statements failed, marking job as failed")
            sys.exit(1)
            
    except Exception as e:
        logger.error(f"Job failed: {e}")
        sys.exit(1)
    finally:
        if spark:
            spark.stop()

if __name__ == "__main__":
    main()
