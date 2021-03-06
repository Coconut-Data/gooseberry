
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
      break unless question? and @shouldSkip(question)

    if question?
      @data.messagesSent.push
        questionIndex: question.index
        text: question.label
    else
      @data.complete = true
    @save()
    question

  shouldSkip: (question) =>
    # Do stuff here to setup context for eval (ResultOfQuestion, etc)
    # Might need to reformat skip_logic
    # If this returns true then question should be skipped
    if question.skip_logic
      Coffeescript.eval(question.skip_logic) 

  validate: (question, contents) =>
    # Do stuff here to setup context for eval (ResultOfQuestion, etc)
    # Might need to reformat skip_logic
    # If this returns true then question should be skipped
    if question.validate
      Coffeescript.eval(question.validate(contents))

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

    @nextQuestion()?.label

  validateAndGetResponse: (messageContents) =>
    currentQuestion = @questionSet.getQuestion(@currentQuestionIndex())
    messageReceived = 
      questionIndex: currentQuestion.index
      text: messageContents
    validationError = @validate(currentQuestion, messageContents)
    if validationError
      messageReceived.valid = false
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
      @nextQuestion()?.label

  summaryString: =>
    result = "#{@data.gateway} - #{@questionSet.label()} - #{@data.source} - #{if @data.complete then "complete" else "incomplete"}\n"
    for sent in @data.messagesSent

      relevantReceivedMessage = @data.messagesReceived.find (messageReceived) =>
        messageReceived.questionIndex is sent.questionIndex and not messageReceived.invalid

      result += "#{sent.text}: #{relevantReceivedMessage.text}\n"
    result


class QuestionSetTable
  constructor: (@databaseTable) ->
  get: (name) =>
    @databaseTable.get(name)

class QuestionSet
  constructor: (@data) ->

  label: => @data.label

  getQuestion: (index) =>
    if @data.questions[index]?
      {...@data.questions[index], index: index}


module.exports = {Message, DatabaseTable, InteractionTable, Interaction, QuestionSetTable, QuestionSet}
