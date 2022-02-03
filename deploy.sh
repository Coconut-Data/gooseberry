#!/usr/bin/bash
#coffee -c index.coffee
#coffee -c --bare gooseberry.coffee
webpack --config webpack.config.js
echo 'webpack finished'
sleep 2
pushd dist; zip -q lambdaFunction.zip index.js 
aws lambda update-function-code --function-name gooseberry --zip-file fileb://lambdaFunction.zip; popd
