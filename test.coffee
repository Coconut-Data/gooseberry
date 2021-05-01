`const {InteractionTable, Interaction, QuestionSet} = require('./gooseberry')`
`const {DynamoDBClient} = require("@aws-sdk/client-dynamodb")`

Assert = require 'assert'

fixtures = (=> 
  {
    "Configuration":
      gatewayName: "Web"
      username: "admin"
      password: "password"
      phoneNumber: "424242"

      "Question Sets":
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
              validation: "'Your name is too long' if value.length > 10" 
            }
          ]
        "Radio": 
          label: "Radio"
          version: "1"
          "complete_message": "Thanks, I hope you go to \#{ResultOfQuestion('Favorite Country')} and not \#{ResultOfQuestion('Least Favorite Place')}"
          questions: [
            {
              label: "Favorite Country?"
              type: "radio"
              "radio-options": "USA, Kenya, Austria, UK"
            }
            {
              label: "Least Favorite Place?"
              calculated_label: "What is your least favorite place? Dayton or Winnemucca?"
              type: "radio"
              "radio-options": "Dayton, Winnemucca"
            }
            {
              label: "Do you like trying new food?"
              type: "radio"
              "radio-options": "Yes, No"
            }
          ]
        "Number": 
          label: "Number"
          version: "1"
          questions: [
            {
              label: "What is the best number?"
              type: "number"
            }
          ]
        "NoFuzz": 
          label: "Radio"
          version: "1"
          questions: [
            {
              label: "Favorite Country?"
              type: "radio"
              disable_fuzzy_search: true
              "radio-options": "USA, Kenya, Austria, UK"
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
    questionSetsByUpperCaseName = {}
    for name, data of @gateway["Question Sets"]
      questionSetsByUpperCaseName[name.toUpperCase()] = data
    questionSetsByUpperCaseName[questionSetName.toUpperCase()]

  getResponse: (phoneNumber, message) =>
    interaction = await Interaction.startNewOrFindIncomplete(phoneNumber, message)
    interaction.validateAndGetResponse()


global.gooseberry = new Gooseberry(fixtures["Configuration"])


phoneNumber = "+13103905996"

summaryString = =>
  (await gooseberry.interactionTable.getLatestInteractionForSource(phoneNumber)).summaryString()

Assert.responseIs = (text, expectedResponse) =>
  console.log "--> #{text}"
  response = await gooseberry.getResponse(phoneNumber,text)
  console.log "<-- #{response}"
  Assert.equal response, expectedResponse

Assert.responsesAre = (textAndResponses) =>
  while textAndResponses.length > 0
    text = textAndResponses.shift()
    expectedResponse = textAndResponses.shift()
    await Assert.responseIs text, expectedResponse

global.oldTests = =>
  await Assert.responseIs "Start Names", "First Name"

  await Assert.responsesAre [
    "Start Names"
    "First Name"
    "Mike",
    "Mike, What is your middle name?"
    "Vonderohe"
    "Last Name"
    "McKay"
    ""
  ]

  await Assert.responsesAre [
    "Start Names"
    "First Name"
    "Pete"
    "Last Name"
    "RepeatPeteRepeat"
    "Your name is too long"
    "RepeatPete"
    ""
  ]

  await Assert.responsesAre [
    "Start Nonexistent"
    "Sorry, there is no question set named 'Nonexistent'"
  ]

  await Assert.responsesAre [
    "Start Names"
    "First Name"
    "Mike"
    "Mike, What is your middle name?"
    "Vonderohe"
    "Last Name"
    "McKay"
    ""
    "Poopy Pants"
    "No open question set for #{phoneNumber}. 'Names' is complete. You can restart it with 'Start Names'."
  ]

  interaction = await Interaction.startNewOrFindIncomplete("6969", "Send me money")
  result = await interaction.validateAndGetResponse()
  Assert.equal result, "No open question set for 6969, no action for 'Send me money'. Try: 'Start Test Questions'."

global.radioTests = =>
  await Assert.responsesAre [
    "Start Radio"
    "Favorite Country? [USA, Kenya, Austria, UK]"
    "Germany"
    "Value must be USA or Kenya or Austria or UK, you sent 'Germany'"
    "austria "
    "What is your least favorite place? Dayton or Winnemucca?"
    "Dayton"
    "Do you like trying new food? [Yes, No]"
    "y"
    "Thanks, I hope you go to Austria and not Dayton"
  ]

  await Assert.responsesAre [
    "Start Radio"
    "Favorite Country? [USA, Kenya, Austria, UK]"
    "Kanye"
    "What is your least favorite place? Dayton or Winnemucca?"
    "Reno"
    "Value must be Dayton or Winnemucca, you sent 'Reno'"
    "Winnemucca"
    "Do you like trying new food? [Yes, No]"
    "yes"
    "Thanks, I hope you go to Kenya and not Winnemucca"
  ]

  await Assert.responsesAre [
    "Start NoFuzz"
    "Favorite Country? [USA, Kenya, Austria, UK]"
    "Kenye"
    "Value must be USA or Kenya or Austria or UK, you sent 'Kenye'"
  ]


global.numberTests = =>
  await Assert.responsesAre [
    "Start Number"
    "What is the best number?"
    "Dunno"
    "Value must be a number, you sent 'Dunno'"
    "1"
    ""
  ]

( =>
  if process.argv?[2]? and process.argv[2] isnt "--all"
    await global[process.argv[2].replace(/--/,"")]()
  else
    await oldTests()
    await radioTests()
    await numberTests()
)()

