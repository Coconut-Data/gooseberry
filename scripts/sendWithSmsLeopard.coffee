send = (options) =>
  new Promise (resolve, reject) =>
    to = encodeURI(options.to)
    message = encodeURI(options.message)
    https = require('https')
    https.request(
      'method': 'GET'
      'hostname': 'api.smsleopard.com'
      'path': "/v1/sms/send?message=#{message}&destination=#{to}&source=24971&username=ITjp3cvCubJ3Gl1EeEvs&password=QIPveZIvbAcnZab5keR0ajkLgj76HbDCh0wAh6hU"
      'headers': {}
      'maxRedirects': 20
    , (response) =>
      chunks = []
      response.on 'data', (chunk) => chunks.push(chunk)
      response.on 'end', (chunk) => resolve(Buffer.concat(chunks).toString())
      response.on 'error', (error) => reject(error)
    ).end()

( =>
  console.log await send
    to: "+254716925547"
    message: "AP to the EYE"
)()
