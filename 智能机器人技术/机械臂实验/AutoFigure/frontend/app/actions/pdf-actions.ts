"use server"

// Remote API URL for PDF to Markdown conversion - configure via environment variable
const PDF_API_URL = process.env.PDF_API_URL || ""

export interface PdfToMarkdownResult {
    success: boolean
    markdown?: string
    error?: string
    usedFallback?: boolean
}

/**
 * Server Action to convert PDF to Markdown using remote API.
 * Server Actions can handle larger files than API routes with proper configuration.
 * Falls back to returning file info if remote API fails (client will use local extraction).
 */
export async function convertPdfToMarkdown(formData: FormData): Promise<PdfToMarkdownResult> {
    try {
        const pdfFile = formData.get("pdf_file")

        if (!pdfFile || !(pdfFile instanceof File)) {
            return {
                success: false,
                error: "No PDF file provided",
            }
        }

        const fileSizeMB = pdfFile.size / (1024 * 1024)
        console.log(`[PDF Action] Processing PDF file: ${pdfFile.name}, size: ${fileSizeMB.toFixed(2)} MB`)

        // Check file size limit (50MB)
        if (fileSizeMB > 50) {
            return {
                success: false,
                error: "PDF file is too large. Maximum size is 50MB.",
            }
        }

        // Check if remote API URL is configured
        if (!PDF_API_URL || PDF_API_URL.trim() === "") {
            console.log("[PDF Action] No remote PDF API URL configured, client will use local extraction")
            return {
                success: false,
                error: "Remote PDF API not configured",
                usedFallback: true,
            }
        }

        // Forward to remote API
        const remoteFormData = new FormData()
        remoteFormData.append("pdf_file", pdfFile)

        console.log("[PDF Action] Forwarding to remote API...")

        const response = await fetch(PDF_API_URL, {
            method: "POST",
            body: remoteFormData,
            // Add timeout to avoid hanging
            signal: AbortSignal.timeout(120000), // 2 minutes timeout
        })

        if (!response.ok) {
            const errorText = await response.text()
            console.error("[PDF Action] Remote API error:", response.status, errorText)

            // If 413 (file too large for nginx), suggest using fallback
            if (response.status === 413) {
                return {
                    success: false,
                    error: "Remote API file size limit exceeded. Please use local extraction or contact admin to increase nginx client_max_body_size.",
                    usedFallback: true,
                }
            }

            return {
                success: false,
                error: `Remote API returned ${response.status}`,
            }
        }

        const result = await response.json()
        console.log("[PDF Action] Successfully received response from remote API")

        if (result.markdown) {
            return {
                success: true,
                markdown: result.markdown,
            }
        } else {
            return {
                success: false,
                error: result.error || "Remote API did not return markdown",
            }
        }
    } catch (error) {
        console.error("[PDF Action] Error:", error)
        return {
            success: false,
            error: `PDF processing failed: ${error}`,
        }
    }
}
