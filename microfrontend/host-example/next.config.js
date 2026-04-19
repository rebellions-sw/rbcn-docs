// Host (demo-nextjs) 의 next.config.js 예시
// ENV 변수는 ConfigMap 으로 주입.

const { NextFederationPlugin } = require('@module-federation/nextjs-mf');

const remotes = (env) => ({
  billing:   `billing@${env.MFE_BILLING_URL || 'http://localhost:3001'}/_next/static/chunks/remoteEntry.js`,
  analytics: `analytics@${env.MFE_ANALYTICS_URL || 'http://localhost:3002'}/_next/static/chunks/remoteEntry.js`,
});

module.exports = {
  reactStrictMode: true,
  webpack(config, options) {
    if (!options.isServer) {
      config.plugins.push(
        new NextFederationPlugin({
          name: 'host',
          remotes: remotes(process.env),
          shared: {
            react: { singleton: true, requiredVersion: false },
            'react-dom': { singleton: true, requiredVersion: false },
          },
          extraOptions: { exposePages: false, automaticAsyncBoundary: true },
        }),
      );
    }
    return config;
  },
};
