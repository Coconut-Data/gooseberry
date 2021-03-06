Classes = require './index'

Message = Classes.Message
DatabaseTable = Classes.DatabaseTable
InteractionTable = Classes.InteractionTable
Interaction = Classes.Interaction
QuestionSetTable = Classes.QuestionSetTable
QuestionSet = Classes.QuestionSet

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
        label: "Last Name"
        type: "text"
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

phoneNumber = "+13103905996"
gateway = "Malawi:SMS"

send = (message) =>
  message = new Message(gateway, phoneNumber, message)
  message.processMessageAndGetResponse()

dumpDB = =>
  console.log JSON.stringify(Gooseberry.interactionTables["Malawi:SMS"].databaseTable.data, null, 2)


response = send "START Names"
Assert.equal response, "First Name"
Assert Object.keys(Gooseberry.interactionTables["Malawi:SMS"].databaseTable.data).length > 1


response = send "Mike"
Assert.equal response, "Last Name"

response = send "McKay"
Assert response is undefined
#dumpDB()

response = send "START Names"
response = send "Mike"
response = send "VdoMcK"

#dumpDB()

console.log Gooseberry.interactionTables["Malawi:SMS"].getLatestInteractionForSource(phoneNumber).summaryString()

