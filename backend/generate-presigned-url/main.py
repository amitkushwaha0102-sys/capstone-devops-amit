import json
import boto3
import uuid
from botocore.exceptions import ClientError

s3_client = boto3.client('s3', region_name='us-east-1')

BUCKET_NAME = 'devops-accelerator-uploads-amit2700'  # baad mein terraform se aayega

def lambda_handler(event, context):
    try:
        file_name = str(uuid.uuid4()) + '.csv'
        
        presigned_url = s3_client.generate_presigned_url(
            'put_object',
            Params={
                'Bucket': BUCKET_NAME,
                'Key': f'uploads/{file_name}',
                'ContentType': 'text/csv'
            },
            ExpiresIn=300  # 5 minutes valid rahegi URL
        )
        
        return {
            'statusCode': 200,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Allow-Methods': 'GET, POST, OPTIONS'
            },
            'body': json.dumps({
                'upload_url': presigned_url,
                'file_name': file_name
            })
        }
        
    except ClientError as e:
        return {
            'statusCode': 500,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'error': str(e)})
        }# updated
