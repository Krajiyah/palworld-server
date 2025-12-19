"""
Lambda function to handle EC2 Spot Instance interruption warnings
Triggers immediate backup to S3 before instance terminates
"""

import json
import logging
import boto3
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ssm = boto3.client('ssm')
ec2 = boto3.client('ec2')

def lambda_handler(event, context):
    """
    Handle Spot interruption warning - trigger immediate backup
    We have 2 minutes from warning to termination
    """
    try:
        logger.info(f"Spot interruption warning received: {json.dumps(event)}")

        instance_id = event['detail']['instance-id']
        action = event['detail']['instance-action']

        logger.info(f"Instance {instance_id} will be {action} in ~2 minutes")

        # Trigger backup script via SSM
        backup_command = f"""
        #!/bin/bash
        set -e

        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        BACKUP_DIR="/tmp/palworld-backup-$TIMESTAMP"
        S3_BUCKET="{os.environ['S3_BUCKET']}"

        echo "Creating emergency backup due to Spot interruption..."

        # Create backup directory
        mkdir -p $BACKUP_DIR

        # Copy game saves
        if [ -d "/mnt/palworld-data/Pal/Saved" ]; then
            cp -r /mnt/palworld-data/Pal/Saved $BACKUP_DIR/

            # Upload to S3
            aws s3 sync $BACKUP_DIR s3://$S3_BUCKET/emergency-backups/$TIMESTAMP/ \
                --storage-class STANDARD_IA

            echo "Emergency backup completed: s3://$S3_BUCKET/emergency-backups/$TIMESTAMP/"
        else
            echo "No save data found to backup"
        fi

        # Cleanup
        rm -rf $BACKUP_DIR
        """

        # Send command via SSM (if SSM agent is installed)
        try:
            response = ssm.send_command(
                InstanceIds=[instance_id],
                DocumentName='AWS-RunShellScript',
                Parameters={'commands': [backup_command]},
                TimeoutSeconds=110,  # Leave 10 seconds buffer before termination
                Comment=f'Emergency backup due to Spot interruption'
            )

            command_id = response['Command']['CommandId']
            logger.info(f"Backup command sent: {command_id}")

            return {
                'statusCode': 200,
                'body': json.dumps({
                    'instance_id': instance_id,
                    'command_id': command_id,
                    'message': 'Emergency backup initiated'
                })
            }

        except Exception as ssm_error:
            logger.warning(f"SSM command failed (normal if agent not running): {str(ssm_error)}")
            logger.info("Relying on user-data backup script and cron jobs")

            return {
                'statusCode': 200,
                'body': json.dumps({
                    'instance_id': instance_id,
                    'message': 'SSM unavailable, relying on periodic backups'
                })
            }

    except Exception as e:
        logger.error(f"Error handling spot interruption: {str(e)}", exc_info=True)

        # Don't raise - we don't want to fail the interruption process
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

import os  # Import at top would be better, but keeping logic clear
