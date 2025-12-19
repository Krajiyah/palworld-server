"""
Lambda function to attach persistent EBS volume to new EC2 instance
Triggered by Auto Scaling Group lifecycle hook during instance launch
"""

import json
import logging
import time
import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ec2 = boto3.client('ec2')
autoscaling = boto3.client('autoscaling')

def lambda_handler(event, context):
    """
    Handle ASG lifecycle hook to attach EBS volume to new instance
    """
    try:
        logger.info(f"Received event: {json.dumps(event)}")

        # Parse SNS message
        message = json.loads(event['Records'][0]['Sns']['Message'])

        # Skip test notifications
        if message.get('Event') == 'autoscaling:TEST_NOTIFICATION':
            logger.info("Received test notification, skipping...")
            return {'statusCode': 200, 'body': 'Test notification'}

        instance_id = message['EC2InstanceId']
        lifecycle_hook_name = message['LifecycleHookName']
        auto_scaling_group_name = message['AutoScalingGroupName']
        lifecycle_action_token = message.get('LifecycleActionToken')

        logger.info(f"Processing instance {instance_id} in ASG {auto_scaling_group_name}")

        # Get the data volume by tag
        volumes = ec2.describe_volumes(
            Filters=[
                {'Name': 'tag:Persistent', 'Values': ['true']},
                {'Name': 'tag:AutoAttach', 'Values': ['true']}
            ]
        )

        if not volumes['Volumes']:
            logger.error("No persistent data volume found!")
            complete_lifecycle_action(
                auto_scaling_group_name,
                lifecycle_hook_name,
                lifecycle_action_token,
                instance_id,
                'ABANDON'
            )
            return {'statusCode': 500, 'body': 'Volume not found'}

        volume_id = volumes['Volumes'][0]['VolumeId']
        volume_state = volumes['Volumes'][0]['State']
        device_name = '/dev/xvdf'

        logger.info(f"Found volume {volume_id} in state {volume_state}")

        # Detach volume if attached to another instance
        if volume_state == 'in-use':
            attachments = volumes['Volumes'][0].get('Attachments', [])
            if attachments:
                old_instance_id = attachments[0]['InstanceId']
                logger.info(f"Detaching volume from old instance {old_instance_id}")

                ec2.detach_volume(VolumeId=volume_id, Force=True)

                # Wait for detachment
                waiter = ec2.get_waiter('volume_available')
                waiter.wait(VolumeIds=[volume_id], WaiterConfig={'Delay': 5, 'MaxAttempts': 30})

        # Wait for instance to be in running state
        logger.info("Waiting for instance to be running...")
        instance_waiter = ec2.get_waiter('instance_running')
        instance_waiter.wait(InstanceIds=[instance_id], WaiterConfig={'Delay': 5, 'MaxAttempts': 30})

        # Attach volume to new instance
        logger.info(f"Attaching volume {volume_id} to instance {instance_id} as {device_name}")
        ec2.attach_volume(
            VolumeId=volume_id,
            InstanceId=instance_id,
            Device=device_name
        )

        # Wait for attachment to complete
        waiter = ec2.get_waiter('volume_in_use')
        waiter.wait(VolumeIds=[volume_id], WaiterConfig={'Delay': 5, 'MaxAttempts': 30})

        logger.info("Volume attached successfully!")

        # Complete lifecycle action successfully
        complete_lifecycle_action(
            auto_scaling_group_name,
            lifecycle_hook_name,
            lifecycle_action_token,
            instance_id,
            'CONTINUE'
        )

        return {
            'statusCode': 200,
            'body': json.dumps({
                'instance_id': instance_id,
                'volume_id': volume_id,
                'status': 'attached'
            })
        }

    except Exception as e:
        logger.error(f"Error: {str(e)}", exc_info=True)

        # Try to complete lifecycle action with ABANDON
        try:
            complete_lifecycle_action(
                auto_scaling_group_name,
                lifecycle_hook_name,
                lifecycle_action_token,
                instance_id,
                'ABANDON'
            )
        except:
            pass

        raise

def complete_lifecycle_action(asg_name, hook_name, token, instance_id, result):
    """
    Complete the lifecycle action to allow instance to continue or terminate
    """
    try:
        params = {
            'LifecycleHookName': hook_name,
            'AutoScalingGroupName': asg_name,
            'LifecycleActionResult': result,
            'InstanceId': instance_id
        }

        if token:
            params['LifecycleActionToken'] = token

        autoscaling.complete_lifecycle_action(**params)
        logger.info(f"Lifecycle action completed with result: {result}")
    except ClientError as e:
        logger.error(f"Failed to complete lifecycle action: {str(e)}")
        raise
