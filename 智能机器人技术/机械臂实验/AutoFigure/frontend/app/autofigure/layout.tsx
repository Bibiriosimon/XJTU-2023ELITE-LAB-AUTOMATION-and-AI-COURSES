import type { Metadata } from "next"

export const metadata: Metadata = {
    title: "AutoFigure - Auto-generate · Free to edit",
    description: "Generate professional scientific figures from scientific materials using AI. Automatic layout generation, free to edit, and AI-powered beautification.",
    keywords: [
        "AutoFigure",
        "scientific figure",
        "research paper",
        "AI diagram",
        "figure generation",
        "academic visualization"
    ],
    authors: [{ name: "WestlakeNLP" }],
    creator: "WestlakeNLP",
    publisher: "WestlakeNLP",
    icons: [],
}

export default function AutoFigureLayout({
    children,
}: {
    children: React.ReactNode
}) {
    return <>{children}</>
}
