`const {Message,DatabaseTable,InteractionTable, Interaction, QuestionSetTable, QuestionSet} = require('./gooseberry')`

Assert = require 'assert'

fixtures = (=> 
  source = "+254716925547"
  startTime = 1614939527318
  questionSet =
    label: "Names"
    questions: [
      {
        label: "First Name"
        type: "text"
      }
      {
        label: "Middle Name"
        calculated_label: "\#{ResultOfQuestion('First Name')}, What is your middle name?"
        skip_logic: "ResultOfQuestion('First Name') is 'Pete'"
        type: "text"
      }
      {
        label: "Last Name"
        type: "text"
        validate: "'Your name is too long' if value.length > 10" 
      }
    ]

  return {

    "Configuration":
      gateways:
        "Malawi:SMS":
          username: "admin"
          password: "password"
          phoneNumber: "424242"

    "Malawi:SMS":
      "#{source}, #{startTime}": 
        startTime: " 10:10:00"
        source: "+254716925547"
        questionSet: questionSet
        messagesReceived: [
          {
            questionIndex: null
            text: "START"
          }
        ]
        messagesSent: [
          {
            questionIndex: 0
            text: "First Name"
          }
        ]
        complete: false

    "Question Sets":
      "Names": questionSet
  }
)()


questionSets = new QuestionSetTable(
  new DatabaseTable(
    fixtures["Question Sets"]
  )
)

configuration = new DatabaseTable(
  fixtures["Configuration"]
)

global.Gooseberry =
  interactionTables: {}
  questionSets: new QuestionSetTable(
    new DatabaseTable(
      fixtures["Question Sets"]
    )
  )


for gateway, gatewayData of (configuration.get "gateways")
  Gooseberry.interactionTables[gateway] = new InteractionTable(
    new DatabaseTable(
      fixtures[gateway]
    )
  )

#### TESTS ####
#
(test = =>

  phoneNumber = "+13103905996"
  gateway = "Malawi:SMS"

  send = (message) =>
    message = new Message(gateway, phoneNumber, message)
    message.processMessageAndGetResponse()

  dumpDB = =>
    console.log JSON.stringify(Gooseberry.interactionTables["Malawi:SMS"].databaseTable.data, null, 2)


  Assert.responseIs = (text, expectedResponse) =>
    console.log "--> #{text}"
    response = await send(text)
    console.log "<-- #{response}"
    Assert.equal response, expectedResponse

  Assert.responsesAre = (textAndResponses) =>
    for text, expectedResponse of textAndResponses
      await Assert.responseIs text, expectedResponse

  await Assert.responseIs "Start Names", "First Name"

  Assert Object.keys(Gooseberry.interactionTables["Malawi:SMS"].databaseTable.data).length > 1

  await Assert.responsesAre
    "Mike":"Mike, What is your middle name?"
    "Vonderohe": "Last Name"
    "McKay": ""
  console.log Gooseberry.interactionTables["Malawi:SMS"].getLatestInteractionForSource(phoneNumber).summaryString()

  await setTimeout =>
    new Promise (resolve) =>
      resolve()
  , 100

  await Assert.responsesAre
    "Start Names":"First Name"
    "Pete":"Last Name"
    "RepeatPeteRepeat": "Your name is too long"
    "RepeatPete": ""

  dumpDB()

  #console.log Gooseberry.interactionTables["Malawi:SMS"].getLatestInteractionForSource(phoneNumber).summaryString()
)()

