// Remote (rbcn-mfe-<name>) 의 next.config.js 예시.

const { NextFederationPlugin } = require('@module-federation/nextjs-mf');

module.exports = {
  reactStrictMode: true,
  output: 'standalone',
  webpack(config, options) {
    if (!options.isServer) {
      config.plugins.push(
        new NextFederationPlugin({
          name: 'billing', // CHANGE ME (host의 remote key 와 일치)
          filename: 'static/chunks/remoteEntry.js',
          exposes: {
            './Page':    './app/exposed/page.tsx',
            './Widget':  './app/exposed/widget.tsx',
          },
          shared: {
            react: { singleton: true, requiredVersion: false },
            'react-dom': { singleton: true, requiredVersion: false },
          },
        }),
      );
    }
    return config;
  },
};
