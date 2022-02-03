// Webpack uses this to work with directories
const path = require('path');

// This is the main configuration object.
// Here, you write different options and tell Webpack what to do
module.exports = {

  // Path to your entry point. From this file Webpack will begin its work
  //entry: './index.js',
  entry: './index.coffee',

  // Path and filename of your result bundle.
  // Webpack will bundle all JavaScript into this file
  output: {
    // Couldn't find handler without libraryTarget
    libraryTarget: 'commonjs',
    path: path.resolve(__dirname, 'dist'),
    publicPath: '',
    filename: 'index.js'
  },
  mode: 'production',
  optimization: {
    minimize: false,
  },
  target: 'node',
  node: false,
  module: {
    rules: [
      {
        test: /\.coffee$/,
        loader: 'coffee-loader',
      },
    ],
  },
  resolve: {
    extensions: [ '.js', '.coffee' ]
  }
};
