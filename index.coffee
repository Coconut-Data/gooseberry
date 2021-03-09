Coffeescript = require 'coffeescript'

class Message
  constructor: ( @gateway, @source, @contents) ->

  processMessageAndGetResponse: =>
    if startMessage = @contents.match(/^ *START +(.*)/i)
      questionSetName = startMessage[1]
      @interaction = new Interaction(
        gateway: @gateway
        source: @source
      )
      @interaction.start(
        messageContents: @contents
        questionSetName: questionSetName
      )
    else
      @interaction = Gooseberry.interactionTables[@gateway]?.getLatestInteractionForSource(@source)
      @interaction.validateAndGetResponse(@contents)

class DatabaseTable
  constructor: (@data) ->

  get: (key) => @data[key]

  put: (key,value) => 
    @data[key] = value

  getAllWithFirstKey: (firstKey) =>
    result = []
    for key,value of @data
      result.push {"#{key}":value} if key.split(", ")[0] is firstKey
    return result

class InteractionTable
  constructor: (@databaseTable) ->

  getLatestInteractionForSource: (source) =>
    # https://stackoverflow.com/questions/12079192/getting-the-last-element-of-an-array-in-coffeescript/30244884
    [..., latest] = @databaseTable.getAllWithFirstKey(source)
    interactionData = Object.values(latest)?[0]
    new Interaction(interactionData)

  put: (interaction) =>
    @databaseTable.put interaction.key(),interaction.data


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
        questionIndex: question.index
        text: textToSend
    else
      @data.complete = true
    @save()
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
    Gooseberry.interactionTables[@data.gateway].put(@)

  start: (options) =>
    questionSet = Gooseberry.questionSets.get(options.questionSetName)
    throw "Invalid Question Set: #{options.questionSetName}" unless questionSet
    @questionSet = new QuestionSet(questionSet)

    @data = {...@data, 
      ...{
        startTime: Date.now()
        questionSet: questionSet
        messagesReceived: [
          questionIndex: -1
          text: options.messageContents
        ]
        messagesSent: []
      }
    }

    @nextQuestion()

  validateAndGetResponse: (messageContents) =>
    currentQuestion = @questionSet.getQuestion(@currentQuestionIndex())
    messageReceived = 
      questionIndex: currentQuestion.index
      text: messageContents
    validationError = await @validate(currentQuestion, messageContents)
    if validationError
      messageReceived.invalid = true
      @data.messagesReceived.push messageReceived
      @data.messagesSent.push
        questionIndex: currentQuestion.index
        text: validationError
        invalidMessage: messageContents
        invalid: true
      @save()
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

class QuestionSetTable
  constructor: (@databaseTable) ->
  get: (name) =>
    @databaseTable.get(name)

class QuestionSet
  constructor: (@data) ->

  label: => @data.label

  # Also returns the index
  getQuestion: (index) =>
    if @data.questions[index]?
      {...@data.questions[index], index: index}

module.exports = {Message, DatabaseTable, InteractionTable, Interaction, QuestionSetTable, QuestionSet}
