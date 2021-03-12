`const {InteractionTable, Interaction, QuestionSet} = require('./gooseberry')`
`const {DynamoDBClient} = require("@aws-sdk/client-dynamodb")`

Assert = require 'assert'

fixtures = (=> 
  questionSet =
    label: "Names"
    version: "1"
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
      gatewayName: "Web"
      username: "admin"
      password: "password"
      phoneNumber: "424242"

      "Question Sets":
        "Test Questions": 
          label: "Test Questions"
          version: "1"
          questions: [
            {
              label: "Name"
              calculated_label: "What is your name?"
              type: "text"
            }
            {
              label: "Middle Name"
              calculated_label: "\#{ResultOfQuestion('Name')}, What is your middle name?"
              skip_logic: "ResultOfQuestion('First Name') is 'Pete'"
              type: "text"
            }
          ]
        "Names": 
          label: "Names"
          version: "1"
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
  }
)()

class Gooseberry
  constructor: (gatewayConfiguration) ->
    @gateway = gatewayConfiguration
    @dynamoDBClient = new DynamoDBClient() # Probably will already have this to have gotten configuration
    @interactionTable = new InteractionTable(@gateway.gatewayName, @dynamoDBClient)

  getQuestionSetData: (questionSetName) =>
    questionSetData = @gateway["Question Sets"]?[questionSetName]
    throw "Invalid Question Set: #{questionSetName}" unless questionSetData
    questionSetData


global.gooseberry = new Gooseberry(fixtures["Configuration"])

#### TESTS ####
#
(test = =>

  phoneNumber = "+13103905996"

  send = (message) =>
    interaction = await Interaction.startNewOrFindIncomplete(phoneNumber, message)
    interaction.validateAndGetResponse()

  summaryString = =>
    (await gooseberry.interactionTable.getLatestInteractionForSource(phoneNumber)).summaryString()


  Assert.responseIs = (text, expectedResponse) =>
    console.log "--> #{text}"
    response = await send(text)
    console.log "<-- #{response}"
    Assert.equal response, expectedResponse

  Assert.responsesAre = (textAndResponses) =>
    for text, expectedResponse of textAndResponses
      await Assert.responseIs text, expectedResponse

  await Assert.responseIs "Start Names", "First Name"

  await Assert.responsesAre
    "Mike":"Mike, What is your middle name?"
    "Vonderohe": "Last Name"
    "McKay": ""

  console.log await summaryString()

  await Assert.responsesAre
    "Start Names":"First Name"
    "Pete":"Last Name"
    "RepeatPeteRepeat": "Your name is too long"
    "RepeatPete": ""

  await Assert.responsesAre
    "Start Nonexistent":"Sorry, there is no question set named 'Nonexistent'"

  await Assert.responsesAre
    "Start Names":"First Name"
    "Mike":"Mike, What is your middle name?"
    "Vonderohe": "Last Name"
    "McKay": ""
    "Poopy Pants":"No open question set for #{phoneNumber}. 'Names' is complete. You can restart it with 'Start Names'."

    interaction = await Interaction.startNewOrFindIncomplete("6969", "Send me money")
    result = await interaction.validateAndGetResponse()
    Assert.equal result, "No open question set for 6969, no action for 'Send me money'. Try: 'Start Test Questions'."

  #console.log gooseberry.interactionTable.getLatestInteractionForSource(phoneNumber).summaryString()
)()

