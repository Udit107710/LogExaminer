#!/usr/bin/env python3
"""
Production Log Aggregation Job
Processes ingested log data and creates analytical aggregations for business intelligence
"""
import os
import sys
import uuid
import argparse
from datetime import datetime, timezone
from pyspark.sql import SparkSession
from pyspark.sql.functions import col, lit, current_timestamp, count, max as spark_max, min as spark_min
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def create_spark_session():
    """Create Spark session with Iceberg support"""
    return SparkSession.builder \
        .appName(f"LogsAggregationProd-{uuid.uuid4().hex[:8]}") \
        .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions") \
        .config("spark.sql.catalog.iceberg", "org.apache.iceberg.spark.SparkCatalog") \
        .config("spark.sql.catalog.iceberg.type", "hive") \
        .config("spark.sql.catalog.iceberg.uri", os.getenv('HIVE_METASTORE_URIS', 'thrift://localhost:9083')) \
        .config("spark.sql.catalog.iceberg.warehouse", "s3a://data-platform-iceberg-3e1b0c/warehouse/") \
        .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem") \
        .config("spark.hadoop.fs.s3a.aws.credentials.provider", "com.amazonaws.auth.WebIdentityTokenCredentialsProvider") \
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
            logger.info(f"SQL: {statement[:200]}...)" if len(statement) > 200 else f"SQL: {statement}")
            
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
                # DDL/DML statements (CREATE TABLE, etc.)
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

def verify_source_data(spark):
    """Verify that source logs table exists and has data"""
    try:
        # Check if analytics database exists
        databases = spark.sql("SHOW DATABASES").collect()
        database_names = [row['database'] for row in databases if 'analytics' in row['database']]
        
        if not database_names:
            logger.error("Analytics database not found")
            return False, 0
            
        # Check if logs table exists
        tables_df = spark.sql("SHOW TABLES IN analytics")
        table_names = [row['tableName'] for row in tables_df.collect()]
        
        if 'logs' not in table_names:
            logger.error("Source logs table not found in analytics database")
            return False, 0
        
        # Check if logs table has data
        log_count = spark.sql("SELECT COUNT(*) as count FROM analytics.logs").collect()[0]['count']
        
        if log_count == 0:
            logger.warning("No data found in logs table")
            return True, 0
        
        logger.info(f"Found {log_count} records in source logs table")
        return True, log_count
        
    except Exception as e:
        logger.error(f"Error verifying source data: {e}")
        return False, 0

def create_basic_aggregations(spark, log_count):
    """Create basic aggregation tables programmatically if SQL file doesn't exist"""
    try:
        logger.info("Creating basic aggregations programmatically...")
        
        # Create error summary table
        spark.sql("""
            CREATE TABLE IF NOT EXISTS analytics.error_summary
            USING ICEBERG
            AS
            SELECT 
                level,
                source,
                COUNT(*) as error_count,
                MAX(timestamp) as latest_occurrence,
                current_timestamp() as created_at
            FROM analytics.logs 
            WHERE level IN ('ERROR', 'WARN')
            GROUP BY level, source
            ORDER BY error_count DESC
        """)
        
        # Create daily summary table
        spark.sql("""
            CREATE TABLE IF NOT EXISTS analytics.daily_summary
            USING ICEBERG
            AS
            SELECT 
                date_partition,
                level,
                COUNT(*) as log_count,
                current_timestamp() as created_at
            FROM analytics.logs 
            GROUP BY date_partition, level
            ORDER BY date_partition DESC, level
        """)
        
        logger.info("Basic aggregation tables created successfully")
        return True
        
    except Exception as e:
        logger.error(f"Error creating basic aggregations: {e}")
        return False

def run_aggregation(spark, sql_file=None):
    """Main aggregation function"""
    job_start = datetime.now(timezone.utc)
    logger.info(f"🚀 Starting log aggregation job at {job_start}")
    
    try:
        # Verify source data exists
        has_data, log_count = verify_source_data(spark)
        if not has_data:
            logger.error("❌ Source data verification failed")
            return False
            
        if log_count == 0:
            logger.warning("⚠️  No data to aggregate, skipping job")
            return True
        
        logger.info(f"📊 Processing {log_count} log records for aggregation")
        
        # Execute SQL file if provided and exists
        if sql_file and os.path.exists(sql_file):
            logger.info(f"📋 Executing SQL aggregations from: {sql_file}")
            sql_content = read_sql_file(sql_file)
            results = execute_sql_statements(spark, sql_content)
            
            # Log results summary
            successful_statements = len([r for r in results if r['success']])
            total_statements = len(results)
            
            logger.info(f"📈 SQL execution completed: {successful_statements}/{total_statements} statements successful")
            
            # Show failed statements if any
            failed_results = [r for r in results if not r['success']]
            if failed_results:
                logger.warning(f"⚠️  {len(failed_results)} statements failed:")
                for result in failed_results:
                    logger.warning(f"  Statement {result['statement_index']}: {result['statement']}")
                    logger.warning(f"    Error: {result.get('error', 'Unknown error')}")
            
            # If more than half failed, consider job failed
            success_rate = successful_statements / total_statements if total_statements > 0 else 0
            if success_rate < 0.5:
                logger.error("❌ More than half the statements failed")
                return False
                
        else:
            # Create basic aggregations if no SQL file
            logger.info("📋 No SQL file provided, creating basic aggregations")
            if not create_basic_aggregations(spark, log_count):
                return False
        
        # Show summary of created tables
        logger.info("📊 Aggregation tables summary:")
        analytics_tables = spark.sql("SHOW TABLES IN analytics").collect()
        for table in analytics_tables:
            table_name = table['tableName']
            if table_name != 'logs':  # Skip the source table
                try:
                    row_count = spark.sql(f"SELECT COUNT(*) as count FROM analytics.{table_name}").collect()[0]['count']
                    logger.info(f"  📋 {table_name}: {row_count} rows")
                except:
                    logger.info(f"  📋 {table_name}: (unable to count rows)")
        
        job_end = datetime.now(timezone.utc)
        duration = (job_end - job_start).total_seconds()
        
        logger.info(f"✅ Aggregation job completed successfully!")
        logger.info(f"⏱️  Duration: {duration:.2f} seconds")
        logger.info(f"📈 Source records processed: {log_count}")
        
        return True
        
    except Exception as e:
        logger.error(f"❌ Error during aggregation: {e}")
        import traceback
        traceback.print_exc()
        return False

def main():
    """Main function"""
    parser = argparse.ArgumentParser(description="Run log aggregation job")
    parser.add_argument("--sql-file", help="Path to SQL file to execute")
    parser.add_argument("--warehouse", help="Iceberg warehouse location (for compatibility)")
    parser.add_argument("--hms-uri", help="Hive Metastore URI (for compatibility)")
    
    args = parser.parse_args()
    
    print("=" * 60)
    print("🔧 Production Log Aggregation Job")
    print("=" * 60)
    
    spark = None
    try:
        # Create Spark session
        spark = create_spark_session()
        
        # Set log level to reduce verbosity
        spark.sparkContext.setLogLevel("WARN")
        
        logger.info(f"✅ Spark session created: {spark.version}")
        logger.info(f"🎯 Application ID: {spark.sparkContext.applicationId}")
        logger.info(f"🏷️  Application Name: {spark.sparkContext.appName}")
        
        # Run aggregation
        success = run_aggregation(spark, args.sql_file)
        
        if success:
            print("🎉 Aggregation job completed successfully!")
            sys.exit(0)
        else:
            print("💥 Aggregation job failed!")
            sys.exit(1)
            
    except Exception as e:
        logger.error(f"💥 Fatal error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
    finally:
        if spark:
            spark.stop()

if __name__ == "__main__":
    main()
