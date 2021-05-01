axios = require('axios')
sub = require('date-fns/sub')
fs = require('fs');

getHeaders = =>
  'Connection': 'keep-alive',
  'X-SMSLEOPARD-ACCOUNT-ID': '5808',
  'Accept': 'application/json, text/plain, */*'
  'X-SMSLEOPARD-TOKEN': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE2NDk4MzM1NzQsImlzX2FkbWluIjpmYWxzZSwibGFuZyI6ImVuLVVTIiwicmVmcmVzaCI6MTYxODMwMTE3NCwic2Vzc2lvbl9pZCI6MjQ2NjAsInN0YXR1cyI6ImFjdGl2ZSIsInVzZXJfaWQiOjYyMjF9.UfVWqguYw-XIXqxYt1qwR5Noi5De8Q3D7Q0o950s1Xk'

formatDate = (date) =>
  date.toISOString()[0..18].replace(/T/," ").replace(/-/g,"/")

getAllMessagesInLastFiveMinutes = =>
  # All UTC
  fiveMinutesAgo = formatDate(sub(new Date(), {minutes:5}))
  now = formatDate(new Date())

  result = await axios
    method: 'get'
    url: "https://api.smsleopard.com/v1/accounts/5808/inbox_messages?from=#{fiveMinutesAgo}&per=1000&to=#{now}&term=24971"
    headers: getHeaders()
  .catch (error) =>
    console.log(error)

  result.data.inbox_messages

getAllUnreadMessagesInLastFiveMinutes = =>
  (await getAllMessagesInLastFiveMinutes()).filter (message) => 
    message.is_read is false

updateReadStatus = (messageId, readStatus) =>
  axios
    method: 'put'
    url: "https://api.smsleopard.com/v1/inbox_message/mark-as-read?id=#{messageId}"
    headers: getHeaders()
    data:
      JSON.stringify("is_read": readStatus)
  .catch (error) =>
    console.log(error)

sendToGooseberryAndMarkAsRead = (options) => 
  axios
    method: 'post'
    url: "https://f9l1259lmb.execute-api.us-east-1.amazonaws.com/gooseberry"
    data: options
  .then (result) =>
    updateReadStatus(options.messageId, true)
    fs.appendFileSync('./loggy.log', JSON.stringify(result))
  .catch (error) =>
    # Don't mark as read so that this can be retried
    console.error error
    fs.appendFileSync('./loggy.log', "ERROR: #{JSON.stringify error}\n")

exports.handler = (event) =>    
  messages = await getAllUnreadMessagesInLastFiveMinutes()

  process.stdout.write if messages.length > 0
    messages.length + " "
  else
    "."

  for message in messages
    # Don't await this, let it send a bunch of parallel requests so Lambda can scale it
    fs.appendFileSync('./loggy.log', "<- #{message.sender}: #{message.message}\n")
    sendToGooseberryAndMarkAsRead
      from: "+#{message.sender}"
      message: message.message
      gateway: "Tusome"
      canSendResponses: false
      messageId: message.messageId

