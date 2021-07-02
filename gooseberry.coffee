Coffeescript = require 'coffeescript'
`const {DynamoDBClient,GetItemCommand,PutItemCommand,QueryCommand} = require("@aws-sdk/client-dynamodb")`

`const format = require("date-fns/format")`
`const differenceInMinutes = require('date-fns/differenceInMinutes')`

`const {marshall, unmarshall} = require("@aws-sdk/util-dynamodb")`
`const Fuse = require('fuse.js')`

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
    currentQuestion = @questionSet.getQuestion(questionIndex)

    #Get the next unskipped question
    loop #basically do...while
      questionIndex += 1
      question = @questionSet.getQuestion(questionIndex)
      break unless question? and await @shouldSkip(question)

    # While it seems like this should be above the loop, we put it here so that we can reset question to null in case the rest of questions need to be skipped
    if currentQuestion.completeQuestionSetIf
      if await @eval(currentQuestion.completeQuestionSetIf,@latestMessageContents) is true
        question = null #This will force it to skip over the questions

    textToSend = ""
    if question?
      textToSend = if question.calculated_label
        await @evalForInterpolatedValues(question.calculated_label) # Allows for dynamic changes to the question
      else if question.type is "radio"
        "#{question.label} [#{question["radio-options"]}]"
      else if question.type is "audio"
        question.url
      else
        question.label

      @data.messagesSent.push
        questionIndex: questionIndex
        text: textToSend
    else
      @data.complete = true
      if @questionSet.data.onValidatedComplete?
        @resultOfOnValidatedComplete = await @eval(@questionSet.data.onValidatedComplete)

      if @questionSet.data.complete_message?
        completeMessage = @questionSet.data.complete_message
        textToSend = if @resultOfOnValidatedComplete?
          await @evalForInterpolatedValues(completeMessage, @resultOfOnValidatedComplete)
        else
          await @evalForInterpolatedValues(completeMessage)

        @data.messagesSent.push
          questionIndex: questionIndex
          text: textToSend

    @updateReportingData()
    await @save()
    textToSend

  updateReportingData: =>
    @data.reporting = {
      source: @data.source
      questionSetName: @data.questionSet.label
      complete: @data.complete or false
      timeStarted: format(@data.startTime, "yyyy-MM-dd HH:mm:ss")
    }

    if @data.complete is true
      completedTimestamp = @data.messagesReceived?[@data.messagesReceived.length-1]?.timestamp
      @data.reporting.timeCompleted = format(completedTimestamp, "yyyy-MM-dd HH:mm:ss")
      @data.reporting.minutesToComplete = differenceInMinutes(completedTimestamp,@data.startTime)
    else
      @data.reporting.minutesSinceStart = differenceInMinutes(Date.now(),@data.startTime)

    for question, index in @questionSet.data.questions
      relevantReceivedMessage = @data.messagesReceived.find (messageReceived) =>
        messageReceived.questionIndex is index and not messageReceived.invalid
      @data.reporting[question.label] = relevantReceivedMessage?.text or "-"


  shouldSkip: (question) =>
    if question.skip_logic
      await @eval(question.skip_logic)

  # null result means that validation was passed
  validate: (question, contents) =>
    validationErrorMessage = if question.validation
      await @eval(question.validation, contents)

    # With radio options we convert any incoming messages to the format of the radio option even if it's a different case
    radioErrorMessage = if question.type is "radio"
      options = question["radio-options"].split(/, */)
      optionsUpperCaseMappedToOriginal = {}
      options.forEach (option) => 
        upperCaseOption = option.toUpperCase()
        optionsUpperCaseMappedToOriginal[upperCaseOption] = option
        # Handle special case of people sending "y" or "n" for a Yes/No queston
        if upperCaseOption is "YES" and contents.toUpperCase() is "Y" then contents = "Yes"
        if upperCaseOption is "NO" and contents.toUpperCase() is "N" then contents = "No"
      upperCaseOptions = Object.keys(optionsUpperCaseMappedToOriginal)
      if upperCaseOptions.includes(contents.toUpperCase())
        @latestMessageContents = optionsUpperCaseMappedToOriginal[contents.toUpperCase()] #Update the incoming message text
        null # null means validation passed
      else
        # Commented out because errors on AWS about Fuse not being a constructor
        #updatedWithFuse = if question.type is "radio" and question.disable_fuzzy_search isnt true
        #  console.log "Loading fuse"
        #  fuse = new Fuse(question["radio-options"].split(/, */), 
        #    includeScore:true
        #    threshold: 0.4
        #  )
        #  if fuse.search(contents)?[0]?.item
        #    @latestMessageContents = fuse.search(contents)?[0]?.item
        updatedWithFuse = false


        if updatedWithFuse
          null # Validated after a fuzzy match
        else if options.join(",").length > 100
          "Value must be #{options.join(",")[0..100]} ...[not all shown], you sent '#{contents}'"
        else
          "Value must be #{options.join(" or ")}, you sent '#{contents}'"

    numberErrorMessage = if question.type is "number"
      if isNaN(contents)
        "Value must be a number, you sent '#{contents}'"
      else
        null

    if validationErrorMessage isnt null or radioErrorMessage isnt null or numberErrorMessage isnt null
      "#{validationErrorMessage or ""}#{radioErrorMessage or ""}#{numberErrorMessage or ""}"
    else
      null

  evalForInterpolatedValues: (codeToEval, value) =>
    @eval("\"#{codeToEval}\"", value)

  eval: (codeToEval, value) =>
    codeToEval = """
(value) ->
  ResultOfQuestion = (question) ->
    #{JSON.stringify @resultsByLabel()}?[question]

  #{codeToEval.replace(/\n/g,"\n  ")}
    """
    await ((Coffeescript.eval(codeToEval, {bare:true}))(value))

  save: =>
    @data.lastUpdate = Date.now()
    gooseberry.interactionTable.put(@)

  validateAndGetResponse: =>
    return @data.error if @data.error?
    currentQuestionIndex = @currentQuestionIndex()
    currentQuestion = @questionSet.getQuestion(currentQuestionIndex)
    # Validate before creating messageReceived so we can update latestMessageContents in some cases
    validationError = await @validate(currentQuestion, @latestMessageContents)
    messageReceived = 
      questionIndex: currentQuestionIndex
      text: @latestMessageContents
      timestamp: Date.now()
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
    result = "#{@data.gateway} - #{@questionSet.label()} - #{@data.source} - #{if @data.complete then "complete" else "incomplete"} - #{@data.startTime}\n"
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
          result[questionLabel.replace(/[^a-zA-Z0-9 ]+/g,"")] = messageReceived.text # Remove non alphanumeric things like punctuation but keep spaces
    result

Interaction.startNewOrFindIncomplete = (source, contents) ->
  # If it's a start message, then setup for a new interaction, otherwise look up from DB
  contents = contents.trim() # Handle extra whitespace
  if startMatch = contents.match(/^ *START +(.*)/i)
    questionSetName = startMatch[1]

    questionSetData = gooseberry.getQuestionSetData(questionSetName)
    unless questionSetData
      return new Interaction(
        error: "Sorry, there is no question set named '#{questionSetName}'"
      )
    interaction = new Interaction(
      source: source
      startTime: Date.now()
      gateway: gooseberry.gateway.gatewayName
      questionSet: questionSetData
      questionSetName: questionSetData.label
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
