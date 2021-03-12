Coffeescript = require 'coffeescript'
`const {DynamoDBClient,GetItemCommand,PutItemCommand,QueryCommand} = require("@aws-sdk/client-dynamodb")`
`const { marshall, unmarshall } = require("@aws-sdk/util-dynamodb")`

class QuestionSet
  constructor: (@data) ->

  label: => @data.label

  getQuestion: (index) =>
    question = if index is -1
      { label: "START", type: "START"} # this data isn't used for anything
    else
      @data.questions[index]

class InteractionTable
  constructor: (@gatewayName, @dynamoDBClient) ->
    @tableName = "Gateway-#{@gatewayName}"

  getLatestInteractionForSource: (source) =>
    result = await @dynamoDBClient.send(
      new QueryCommand
        TableName: @tableName
        KeyConditionExpression: '#src = :source'
        ExpressionAttributeNames:
          "#src":"source" # source is reserved word, hence the gymnastics
        ExpressionAttributeValues:
          ':source':
            'S': source
        ScanIndexForward: false
        Limit: 1
    )

    if result.Items.length > 0
      new Interaction(unmarshall(result.Items[0]))

  put: (interaction) =>
    @dynamoDBClient.send(
      new PutItemCommand(
        TableName: @tableName
        Item: marshall(interaction.data)
      )
    )

# Holds all of the messages for a source and question set response
class Interaction
  constructor: (@data) ->
    if @data?.questionSet
      @questionSet = new QuestionSet(@data.questionSet)

  key: =>
    "#{@data.source}, #{@data.startTime}"

  currentQuestionIndex: =>
    # https://stackoverflow.com/questions/12079192/getting-the-last-element-of-an-array-in-coffeescript/30244884
    if @data.messagesSent.length > 0
      [..., lastMessageSent] = @data.messagesSent
      lastMessageSent.questionIndex
    else
      -1

  nextQuestion: =>
    questionIndex = @currentQuestionIndex()

    loop #basically do...while
      questionIndex += 1
      question = @questionSet.getQuestion(questionIndex)
      break unless question? and await @shouldSkip(question)

    textToSend = ""
    if question?
      textToSend = if question.calculated_label
        await @eval("\"#{question.calculated_label}\"") # Allows for dynamic changes to the question
      else
        question.label

      @data.messagesSent.push
        questionIndex: questionIndex
        text: textToSend
    else
      @data.complete = true
    await @save()
    textToSend

  shouldSkip: (question) =>
    if question.skip_logic
      await @eval(question.skip_logic)

  validate: (question, contents) =>
    if question.validate
      await @eval(question.validate, contents)

  eval: (codeToEval, value) =>
    codeToEval = """
(value) ->
  ResultOfQuestion = (question) ->
    #{JSON.stringify @resultsByLabel()}?[question]

  #{codeToEval}
    """

    await ((Coffeescript.eval(codeToEval, {bare:true}))(value))

  save: =>
    gooseberry.interactionTable.put(@)

  validateAndGetResponse: =>
    return @data.error if @data.error?
    currentQuestionIndex = @currentQuestionIndex()
    currentQuestion = @questionSet.getQuestion(currentQuestionIndex)
    messageReceived = 
      questionIndex: currentQuestionIndex
      text: @latestMessageContents
    validationError = await @validate(currentQuestion, @latestMessageContents)
    if validationError
      messageReceived.invalid = true
      @data.messagesReceived.push messageReceived
      @data.messagesSent.push
        questionIndex: currentQuestionIndex
        text: validationError
        invalidMessage: @latestMessageContents
        invalid: true
      await @save()
      return validationError
    else 
      @data.messagesReceived.push messageReceived
      @nextQuestion()

  summaryString: (debug = false) =>
    console.log @data if debug
    result = "#{@data.gateway} - #{@questionSet.label()} - #{@data.source} - #{if @data.complete then "complete" else "incomplete"}\n"
    for question, index in @questionSet.data.questions

      relevantReceivedMessage = @data.messagesReceived.find (messageReceived) =>
        messageReceived.questionIndex is index and not messageReceived.invalid

      result += "#{question.label}: #{relevantReceivedMessage?.text or null}\n"
    result

  resultsByLabel: =>
    result = {}
    for messageReceived in @data.messagesReceived
      unless messageReceived.valid is false
        questionLabel = @questionSet.data.questions[messageReceived.questionIndex]?.label
        if questionLabel
          result[questionLabel] = messageReceived.text
    result

Interaction.startNewOrFindIncomplete = (source, contents) ->
  # If it's a start message, then setup for a new interaction, otherwise look up from DB
  if startMatch = contents.match(/^ *START +(.*)/i)
    questionSetName = startMatch[1]

    questionSetData = gooseberry.gateway["Question Sets"]?[questionSetName]
    unless questionSetData
      return new Interaction(
        error: "Sorry, there is no question set named '#{questionSetName}'"
      )
    interaction = new Interaction(
      source: source
      startTime: Date.now()
      gateway: gooseberry.gateway.gatewayName
      questionSet: questionSetData
      messagesReceived: []
      messagesSent: []
    )
  else
    interaction = await gooseberry.interactionTable.getLatestInteractionForSource(source)
    unless interaction
      return new Interaction(
        error: "No open question set for #{source}, no action for '#{contents}'. Try: 'Start Test Questions'."
      )
    if interaction.data.complete
      questionSetName = interaction.questionSet.label()
      return new Interaction(
        error: "No open question set for #{source}. '#{questionSetName}' is complete. You can restart it with 'Start #{questionSetName}'."
      )
      
  interaction.latestMessageContents = contents
  return interaction

module.exports = {InteractionTable, Interaction, QuestionSet}
