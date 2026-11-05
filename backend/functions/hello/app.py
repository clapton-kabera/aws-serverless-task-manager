"""
app.py
author: Kabera Clapton

description: A python program that simply returns the string 'hello' in response to an event from
             an API Gateway.
"""

import json

def lambda_handler(event, context):
  method = event["requestContext"]["http"]["method"]
  claims = event["requestContext"]["authorizer"]["jwt"]["claims"]

  if (method == "GET"):
    return {
      "statusCode": 200,
      "headers": {
        "Content-Type": "application/json",
      },
      "body": json.dumps(
        {
          "message": "hello",
          "claims": claims,
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


