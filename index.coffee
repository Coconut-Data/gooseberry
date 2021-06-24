`const {InteractionTable, Interaction, QuestionSet} = require('./gooseberry')`
`const {DynamoDBClient,GetItemCommand, CreateTableCommand} = require("@aws-sdk/client-dynamodb")`
`const {marshall, unmarshall} = require("@aws-sdk/util-dynamodb")`
global.axios = require 'axios'
global.qs = require 'qs'

class Gooseberry
  constructor: (gatewayConfiguration) ->
    @gateway = gatewayConfiguration
    @interactionTable = new InteractionTable(@gateway.gatewayName, @gateway.dynamoDBClient)

  getQuestionSetData: (questionSetName) =>
    questionSetsByUpperCaseName = {}
    for name, data of @gateway["Question Sets"]
      questionSetsByUpperCaseName[name.toUpperCase()] = data
    questionSetsByUpperCaseName[questionSetName.toUpperCase()]

  getResponse: (phoneNumber, message) =>
    interaction = await Interaction.startNewOrFindIncomplete(phoneNumber, message)
    interaction.validateAndGetResponse()


exports.handler = (event) =>
  console.log "Request:"
  console.log JSON.stringify(event, null, 2)
  canSendResponses = true
  [message, source, gateway] = if event.body?
    try
      body = JSON.parse(event.body)
    catch

    twilio = false
    if body?.message? and body?.from?
      console.log body
      if body.canSendResponses?
        canSendResponses = body.canSendResponses
      [body.message, body.from, body.gateway]
    else
      # Twilio
      if event.requestContext?.http?.userAgent is "TwilioProxy/1.1"

        twilio = true
        parsedBody = qs.parse(Buffer.from(event.body,"base64").toString("utf8"))
        console.log "Parsed Body:"
        console.log parsedBody

        if parsedBody.Direction is "outbound-api" # Then Twilio initiated, so reverse to/from values
          to = parsedBody.From
          from = parsedBody.To
        else
          to = parsedBody.To
          from = parsedBody.From

        #Use the Twilio number to get a gateway for each Twilio phone number (SMS and IVR use the same gateway)
        to = "Twilio-#{to.replace(/\+/,"").replace(/:/,"-")}"
        if parsedBody.CallStatus?
          ivr = true
          message = if parsedBody.Digits?
            parsedBody.Digits
          else
            "START IVR" #TODO figure out a way to choose any question set, using voice recognition etc
          [message,from, to] 
        else
          if parsedBody.Body.toUpperCase().match("START IVR")
            dynamoDBClient = new DynamoDBClient()
            result = await dynamoDBClient.send(
              new GetItemCommand(
                TableName: "Configurations"
                Key:
                  gatewayName:
                    "S": to
              )
            )
            configuration = unmarshall(result?.Item)
            {sid,token} = configuration.authentication
            data =
              To: from
              From: configuration.phoneNumber
              Url: "https://f9l1259lmb.execute-api.us-east-1.amazonaws.com/gooseberry"
            url = "https://api.twilio.com/2010-04-01/Accounts/#{sid}/Calls.json"

            await axios.post url, qs.stringify(data), auth:
              username: sid
              password: token

            [null,null,null]
          else
            [parsedBody.Body,from, to]
      else if event.isBase64Encoded #SMSLeopard/Africastalking
        parsedBody = qs.parse(Buffer.from(event.body,"base64").toString("utf8"))
        console.log "Parsed Body:"
        console.log "Parsed Body: #{JSON.stringify(parsedBody)}"
        if parsedBody.to is "3061"
          canSendResponses = false
          [parsedBody.text, parsedBody.from, "Malawi"]
        else if parsedBody.short_code is "24971"
          canSendResponses = false
          [parsedBody.message, parsedBody.sender, "Tusome"]
        else # This one shouldn't be required anymore since SMSLeopard fixed their encoding
          parsedBody = JSON.parse(Object.keys(parsedBody)[0])
          console.log parsedBody
          canSendResponses = false
          [parsedBody.message, "+"+parsedBody.sender, "Tusome"]

  else 
    [event.queryStringParameters?.message, event.queryStringParameters?.from, event.queryStringParameters?.gateway]


  if message is null and  source is null and gateway is null
    # Use this for initiating IVR or for doing other side effects that don't require a SMS response
    return
      statusCode: 204 # 204 means empty response - we don't want to send any more SMS

  unless message?
    return
      statusCode: 200,
      headers: 
        'Content-Type':"text/html"
      body: "Invalid request, no queryStringParameters and no body: #{JSON.stringify event}"

  message = message.trim()

  console.log "'#{message}' from #{source}"

  dynamoDBClient = new DynamoDBClient()

  result = await dynamoDBClient.send(
    new GetItemCommand(
      TableName: "Configurations"
      Key:
        gatewayName:
          "S": gateway
    )
  )
  configuration = unmarshall(result?.Item)
  configuration.dynamoDBClient = dynamoDBClient

  global.gooseberry = new Gooseberry(configuration)
  response = await gooseberry.getResponse(source, message)

  httpResponse = if ivr is true
    statusCode: 200,
    headers: 
      'Content-Type':"text/xml"
    body: "<?xml version='1.0' encoding='UTF-8'?>
      <Response>
        #{
        unless response.startsWith("https://")
          "
          <Gather>
            <Say>#{response}</Say>
          </Gather>
          "
        else
          "
          <Gather>
            <Play>#{response}</Play>
          </Gather>
          "
        }
      </Response>
    "
  else if twilio is true
    statusCode: 200,
    headers: 
      'Content-Type':"text/xml"
    body: "<?xml version='1.0' encoding='UTF-8'?>
      <Response>
        <Message>
            #{response}
        </Message>
      </Response>
    "
  else
    if canSendResponses
      statusCode: 200,
      headers: 
        'Content-Type':"text/html"
      body: response
    else
      configSendResponse = await eval(configuration.send)
        to: source
        message: response

      statusCode: 200
      headers: 
        'Content-Type':"text/html"
      body: "'#{response}' sent via sending API"


  console.log httpResponse
  httpResponse
