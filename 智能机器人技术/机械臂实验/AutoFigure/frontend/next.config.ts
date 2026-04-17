import type { NextConfig } from "next"

const nextConfig: NextConfig = {
    /* config options here */
    output: "standalone",

    async rewrites() {
        return [
            {
                source: "/backend/:path*",
                destination: "http://127.0.0.1:8796/:path*",
            },
        ]
    },

    // Increase body size limit for Server Actions and API routes (for PDF uploads)
    experimental: {
        serverActions: {
            bodySizeLimit: "50mb",
        },
    },
}

export default nextConfig
