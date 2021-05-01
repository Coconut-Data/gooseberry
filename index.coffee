`const {InteractionTable, Interaction, QuestionSet} = require('./gooseberry')`
`const {DynamoDBClient,GetItemCommand, CreateTableCommand} = require("@aws-sdk/client-dynamodb")`
`const {marshall, unmarshall} = require("@aws-sdk/util-dynamodb")`
qs = require 'qs'

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
        to = "Twilio-#{to.replace(/\+/,"")}"
        if parsedBody.CallStatus?
          ivr = true
          message = if parsedBody.Digits?
            parsedBody.Digits
          else
            "START IVR" #TODO figure out a way to choose any question set, using voice recognition etc
          [message,from, to] 
        else
          [parsedBody.Body,from, to]
      else if event.isBase64Encoded #SMSLeopard
        parsedBody = qs.parse(Buffer.from(event.body,"base64").toString("utf8"))
        console.log "Parsed Body:"
        parsedBody = JSON.parse(Object.keys(parsedBody)[0])
        console.log parsedBody
        canSendResponses = false
        [parsedBody.message, "+"+parsedBody.sender, "Tusome"]

  else 
    [event.queryStringParameters?.message, event.queryStringParameters?.from, event.queryStringParameters?.gateway]

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
          <Play>#{response}</Play>
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
