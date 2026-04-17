import { NextRequest, NextResponse } from "next/server"

// Remote API URL for PDF to Markdown conversion - configure via environment variable
const PDF_API_URL = process.env.PDF_API_URL || ""

// App Router configuration for Route Handlers
export const runtime = "nodejs"
export const dynamic = "force-dynamic"
export const maxDuration = 120 // Allow up to 2 minutes for large PDF processing

export async function POST(request: NextRequest) {
    try {
        // Check content length header to provide better error messages
        const contentLength = request.headers.get("content-length")
        if (contentLength) {
            const sizeInMB = parseInt(contentLength) / (1024 * 1024)
            console.log(`[PDF Proxy] Received request with size: ${sizeInMB.toFixed(2)} MB`)

            // Warn if file is very large
            if (sizeInMB > 50) {
                return NextResponse.json(
                    { error: "PDF file is too large. Maximum size is 50MB." },
                    { status: 413 }
                )
            }
        }

        // Get the form data from the request
        const formData = await request.formData()
        const pdfFile = formData.get("pdf_file")

        if (!pdfFile || !(pdfFile instanceof Blob)) {
            return NextResponse.json(
                { error: "No PDF file provided" },
                { status: 400 }
            )
        }

        const fileSizeMB = pdfFile.size / (1024 * 1024)
        console.log(`[PDF Proxy] PDF file size: ${fileSizeMB.toFixed(2)} MB`)

        // Forward to remote API
        console.log("[PDF Proxy] Forwarding PDF to remote API...")

        const remoteFormData = new FormData()
        remoteFormData.append("pdf_file", pdfFile)

        const response = await fetch(PDF_API_URL, {
            method: "POST",
            body: remoteFormData,
        })

        if (!response.ok) {
            const errorText = await response.text()
            console.error("[PDF Proxy] Remote API error:", response.status, errorText)
            return NextResponse.json(
                { error: `Remote API returned ${response.status}: ${errorText}` },
                { status: response.status }
            )
        }

        const result = await response.json()
        console.log("[PDF Proxy] Successfully received response from remote API")

        return NextResponse.json(result)
    } catch (error) {
        console.error("[PDF Proxy] Error:", error)

        // Check if the error is related to body size
        const errorMessage = String(error)
        if (errorMessage.includes("body exceeded") || errorMessage.includes("too large")) {
            return NextResponse.json(
                { error: "PDF file is too large. Please try a smaller file." },
                { status: 413 }
            )
        }

        return NextResponse.json(
            { error: `PDF processing failed: ${error}` },
            { status: 500 }
        )
    }
}
