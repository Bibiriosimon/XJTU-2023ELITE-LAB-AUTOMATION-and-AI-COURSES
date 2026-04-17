"use client"

import { Loader2 } from "lucide-react"
import { useAutoFigure } from "@/contexts/autofigure-context"

export default function GenerationOverlay() {
    const { isGenerating } = useAutoFigure()

    if (!isGenerating) return null

    return (
        <div className="af-generation-overlay">
            <div className="af-generation-spinner-only">
                <Loader2 className="w-12 h-12 animate-spin" />
            </div>
        </div>
    )
}
