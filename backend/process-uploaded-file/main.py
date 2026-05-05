import json
import boto3
import csv
import io
from botocore.exceptions import ClientError

s3_client = boto3.client('s3', region_name='us-east-1')
sns_client = boto3.client('sns', region_name='us-east-1')

SNS_TOPIC_ARN = 'arn:aws:sns:us-east-1:002645521335:capstone-upload-topic'  # baad mein terraform se aayega

def lambda_handler(event, context):
    try:
        # S3 trigger se bucket aur file ka naam milta hai
        bucket = event['Records'][0]['s3']['bucket']['name']
        key = event['Records'][0]['s3']['object']['key']
        
        print(f"Processing file: {key} from bucket: {bucket}")
        
        # File S3 se read karo
        response = s3_client.get_object(Bucket=bucket, Key=key)
        content = response['Body'].read().decode('utf-8')
        
        # CSV rows count karo
        csv_reader = csv.reader(io.StringIO(content))
        rows = list(csv_reader)
        row_count = len(rows) - 1  # header minus
        
        # SNS se email bhejo
        message = f"""
        ✅ File Upload Successful!
        
        File Name : {key}
        Bucket    : {bucket}
        Total Rows: {row_count}
        
        -- Capstone DevOps Platform
        """
        
        sns_client.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject='New File Uploaded - Capstone Platform',
            Message=message
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'File processed successfully',
                'rows_processed': row_count
            })
        }
        
    except ClientError as e:
        print(f"Error: {str(e)}")
        raise e