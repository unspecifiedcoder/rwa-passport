import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  reactStrictMode: true,
  webpack: (config) => {
    // wagmi/connectors tries to import optional wallet SDKs
    // Mark them as external to avoid build failures
    config.resolve.fallback = {
      ...config.resolve.fallback,
      "pino-pretty": false,
      encoding: false,
    };
    config.externals = [...(config.externals || []), "pino-pretty", "encoding"];
    return config;
  },
};

export default nextConfig;
