const webpack = require('webpack');

module.exports = function override(config) {
  // Add fallback for browser polyfills
  config.resolve.fallback = {
    ...config.resolve.fallback,
    zlib: require.resolve('browserify-zlib'),
    path: require.resolve('path-browserify'),
    fs: false,
    vm: require.resolve('vm-browserify'),
    crypto: require.resolve('crypto-browserify'),
    http: require.resolve('stream-http'),
    https: require.resolve('https-browserify'),
    stream: require.resolve('stream-browserify'),
    os: require.resolve('os-browserify/browser'),
    net: false,
    tls: false,
    child_process: false,
  };

  // Add rules for handling fully specified imports in ESM
  config.module.rules = (config.module.rules || []).concat([
    {
      test: /\.m?js$/, // Match both .js and .mjs files
      resolve: {
        fullySpecified: false, // Disable the need for full specification of imports
      },
    },
  ]);

  // Add plugins to provide process and define environment variables
  config.plugins = (config.plugins || []).concat([
    new webpack.ProvidePlugin({
      process: 'process/browser', // Polyfill for process in browser
    }),
    new webpack.DefinePlugin({
      'process.env': JSON.stringify(process.env),
      'process': JSON.stringify({
        env: {
          NODE_ENV: process.env.NODE_ENV,
        },
      }),
    }),
  ]);

  return config;
};