"""
app.py
author: Kabera Clapton

description: A python program that simply returns the string 'hello' in response to an event from
             an API Gateway.
"""

import json

def lambda_handler(event, context):
  method = event["requestContext"]["http"]["method"]

  if (method == "GET"):
    return {
      "statusCode": 200,
      "headers": {
        "Content-Type": "application/json",
      },
      "body": json.dumps(
        {
          "message": "hello",
          "method": method
        }
      )
    }

  return {
    "statusCode": 405,
    "body": json.dumps(
      {
        "message": "not allowed"
      }
    )
  }


