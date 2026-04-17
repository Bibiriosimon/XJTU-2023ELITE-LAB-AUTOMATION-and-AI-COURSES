"use client"

import { useState } from "react"
import {
    ChevronDown,
    ChevronUp,
    FileText,
    Settings2,
    Cpu,
    Palette,
    Play,
    Upload,
    Lightbulb,
} from "lucide-react"
import { useAutoFigure } from "@/contexts/autofigure-context"
import { type ContentType } from "@/lib/autofigure-types"
import { convertPdfToMarkdown } from "@/app/actions/pdf-actions"
import { extractPdfText } from "@/lib/pdf-utils"

interface CollapsibleSectionProps {
    title: string
    icon: React.ReactNode
    children: React.ReactNode
    defaultOpen?: boolean
}

function CollapsibleSection({ title, icon, children, defaultOpen = true }: CollapsibleSectionProps) {
    const [isOpen, setIsOpen] = useState(defaultOpen)

    return (
        <div className="border-b border-slate-700/50 last:border-b-0">
            <button
                onClick={() => setIsOpen(!isOpen)}
                className="w-full flex items-center justify-between py-3 px-1 text-left hover:bg-slate-700/30 rounded transition-colors"
            >
                <div className="flex items-center gap-2 text-sm font-medium text-slate-300">
                    {icon}
                    {title}
                </div>
                {isOpen ? (
                    <ChevronUp className="h-4 w-4 text-slate-500" />
                ) : (
                    <ChevronDown className="h-4 w-4 text-slate-500" />
                )}
            </button>
            {isOpen && <div className="pb-4 space-y-3">{children}</div>}
        </div>
    )
}

interface AutoFigureConfigPanelProps {
    onStart: () => void
}

export default function AutoFigureConfigPanel({ onStart }: AutoFigureConfigPanelProps) {
    const { config, updateConfig, isGenerating, session } = useAutoFigure()
    const [inputText, setInputText] = useState("")
    const [uploadedFile, setUploadedFile] = useState<File | null>(null)
    const [isPdfProcessing, setIsPdfProcessing] = useState(false)

    const handleFileUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
        const file = e.target.files?.[0]
        if (!file) return

        setUploadedFile(file)

        // Read file content
        if (file.type === "text/plain" || file.name.endsWith(".md") || file.name.endsWith(".tex")) {
            const text = await file.text()
            setInputText(text)
        } else if (file.type === "application/pdf") {
            // Use Server Action to extract PDF content, with local fallback
            setIsPdfProcessing(true)
            setInputText(`[Processing PDF: ${file.name}...]`)

            try {
                const formData = new FormData()
                formData.append("pdf_file", file)

                // Try Server Action (remote API) first
                console.log("[AutoFigure] Trying remote API extraction...")
                const result = await convertPdfToMarkdown(formData)

                if (result.success && result.markdown) {
                    setInputText(result.markdown)
                    console.log("[AutoFigure] PDF extraction successful (remote API)")
                } else {
                    // Remote API failed, try local extraction as fallback
                    console.log("[AutoFigure] Remote API failed, trying local extraction...")
                    setInputText(`[Remote API failed, using local extraction...]`)

                    try {
                        const localText = await extractPdfText(file)
                        if (localText && localText.trim()) {
                            setInputText(localText)
                            console.log("[AutoFigure] PDF extraction successful (local fallback)")
                        } else {
                            setInputText(`[PDF extraction failed: No text extracted]`)
                            console.error("[AutoFigure] Local extraction returned empty text")
                        }
                    } catch (localError) {
                        setInputText(`[PDF extraction failed: ${result.error || "Unknown error"}]`)
                        console.error("[AutoFigure] Both remote and local extraction failed:", localError)
                    }
                }
            } catch (error) {
                // Server Action completely failed, try local extraction
                console.log("[AutoFigure] Server Action failed, trying local extraction...")
                try {
                    const localText = await extractPdfText(file)
                    if (localText && localText.trim()) {
                        setInputText(localText)
                        console.log("[AutoFigure] PDF extraction successful (local fallback after error)")
                    } else {
                        setInputText(`[PDF extraction failed: ${error}]`)
                    }
                } catch (localError) {
                    setInputText(`[PDF extraction failed: ${error}]`)
                    console.error("[AutoFigure] PDF extraction error:", error)
                }
            } finally {
                setIsPdfProcessing(false)
            }
        }
    }

    const handleStart = () => {
        if (!inputText.trim()) return
        updateConfig({ inputText })
        onStart()
    }

    const contentTypes: { value: ContentType; label: string }[] = [
        { value: "paper", label: "Research Paper" },
        { value: "survey", label: "Survey Paper" },
        { value: "blog", label: "Blog Post" },
        { value: "textbook", label: "Textbook" },
    ]

    return (
        <div className="h-full flex flex-col bg-slate-800/50 rounded-xl border border-slate-700/50 overflow-hidden">
            {/* Header */}
            <div className="px-4 py-3 border-b border-slate-700/50 bg-slate-800/80">
                <h2 className="text-lg font-semibold text-white flex items-center gap-2">
                    <Settings2 className="h-5 w-5 text-purple-400" />
                    AutoFigure Settings
                </h2>
            </div>

            {/* Content - Scrollable */}
            <div className="flex-1 overflow-y-auto p-4 space-y-1">
                {/* Content Type */}
                <CollapsibleSection
                    title="Content Type"
                    icon={<FileText className="h-4 w-4 text-blue-400" />}
                >
                    <div className="grid grid-cols-2 gap-2">
                        {contentTypes.map(type => (
                            <button
                                key={type.value}
                                onClick={() => updateConfig({ contentType: type.value })}
                                className={`px-3 py-2 text-xs rounded-lg border transition-all ${
                                    config.contentType === type.value
                                        ? "bg-purple-600/20 border-purple-500 text-purple-300"
                                        : "bg-slate-700/30 border-slate-600 text-slate-400 hover:border-slate-500"
                                }`}
                            >
                                {type.label}
                            </button>
                        ))}
                    </div>
                </CollapsibleSection>

                {/* Input Source */}
                <CollapsibleSection
                    title="Input Source"
                    icon={<Upload className="h-4 w-4 text-green-400" />}
                >
                    <div className="space-y-3">
                        <label className="block">
                            <input
                                type="file"
                                accept=".pdf,.txt,.md,.tex"
                                onChange={handleFileUpload}
                                className="hidden"
                                id="file-upload"
                            />
                            <div
                                onClick={() => document.getElementById("file-upload")?.click()}
                                className="flex items-center justify-center gap-2 px-4 py-3 border-2 border-dashed border-slate-600 rounded-lg cursor-pointer hover:border-purple-500 hover:bg-purple-500/5 transition-all"
                            >
                                <Upload className="h-4 w-4 text-slate-400" />
                                <span className="text-sm text-slate-400">
                                    {uploadedFile ? uploadedFile.name : "Upload PDF or Text"}
                                </span>
                            </div>
                        </label>

                        <div className="relative">
                            <textarea
                                value={inputText}
                                onChange={e => setInputText(e.target.value)}
                                placeholder="Or paste your content here..."
                                className="w-full h-32 px-3 py-2 bg-slate-900/50 border border-slate-600 rounded-lg text-sm text-white placeholder-slate-500 resize-none focus:outline-none focus:ring-2 focus:ring-purple-500 focus:border-transparent"
                            />
                            <div className="absolute bottom-2 right-2 text-xs text-slate-500">
                                {inputText.length} chars
                            </div>
                        </div>
                    </div>
                </CollapsibleSection>

                {/* Iteration Settings */}
                <CollapsibleSection
                    title="Iteration Settings"
                    icon={<Settings2 className="h-4 w-4 text-orange-400" />}
                    defaultOpen={false}
                >
                    <div className="space-y-3">
                        <div>
                            <label className="block text-xs text-slate-400 mb-1">Max Iterations</label>
                            <select
                                value={config.maxIterations}
                                onChange={e => updateConfig({ maxIterations: Number(e.target.value) })}
                                className="w-full px-3 py-2 bg-slate-900/50 border border-slate-600 rounded-lg text-sm text-white focus:outline-none focus:ring-2 focus:ring-purple-500"
                            >
                                {[1, 2, 3, 4, 5, 7, 10].map(n => (
                                    <option key={n} value={n}>{n}</option>
                                ))}
                            </select>
                        </div>

                        <div>
                            <label className="block text-xs text-slate-400 mb-1">
                                Quality Threshold: {config.qualityThreshold}
                            </label>
                            <input
                                type="range"
                                min="5"
                                max="10"
                                step="0.5"
                                value={config.qualityThreshold}
                                onChange={e => updateConfig({ qualityThreshold: Number(e.target.value) })}
                                className="w-full accent-purple-500"
                            />
                        </div>

                        <div>
                            <label className="block text-xs text-slate-400 mb-1">
                                Min Improvement: {config.minImprovement}
                            </label>
                            <input
                                type="range"
                                min="0.1"
                                max="1.0"
                                step="0.1"
                                value={config.minImprovement}
                                onChange={e => updateConfig({ minImprovement: Number(e.target.value) })}
                                className="w-full accent-purple-500"
                            />
                        </div>

                        <label className="flex items-center gap-2 cursor-pointer">
                            <input
                                type="checkbox"
                                checked={config.humanInLoop}
                                onChange={e => updateConfig({ humanInLoop: e.target.checked })}
                                className="w-4 h-4 rounded border-slate-600 bg-slate-900 text-purple-500 focus:ring-purple-500"
                            />
                            <span className="text-sm text-slate-300">Human-in-the-Loop</span>
                        </label>
                    </div>
                </CollapsibleSection>

                {/* Methodology Extraction (only for paper content type) */}
                {config.contentType === 'paper' && (
                    <CollapsibleSection
                        title="Methodology Extraction"
                        icon={<Lightbulb className="h-4 w-4 text-yellow-400" />}
                        defaultOpen={false}
                    >
                        <div className="space-y-3">
                            <p className="text-xs text-slate-400">
                                Extract core methodology from paper to improve figure generation quality.
                            </p>

                            <label className="flex items-center gap-2 cursor-pointer">
                                <input
                                    type="checkbox"
                                    checked={config.enableMethodologyExtraction}
                                    onChange={e => updateConfig({ enableMethodologyExtraction: e.target.checked })}
                                    className="w-4 h-4 rounded border-slate-600 bg-slate-900 text-yellow-500 focus:ring-yellow-500"
                                />
                                <span className="text-sm text-slate-300">Enable Methodology Extraction</span>
                            </label>

                            {config.enableMethodologyExtraction && (
                                <>
                                    <div>
                                        <label className="block text-xs text-slate-400 mb-1">Provider</label>
                                        <div className="w-full px-3 py-2 bg-slate-800/50 border border-slate-600 rounded-lg text-sm text-white">
                                            BianXie
                                        </div>
                                    </div>

                                    <div>
                                        <label className="block text-xs text-slate-400 mb-1">Model</label>
                                        <input
                                            type="text"
                                            value={config.methodologyLlmModel}
                                            onChange={e => updateConfig({ methodologyLlmModel: e.target.value })}
                                            placeholder="Enter model name (e.g., gemini-2.5-flash)"
                                            className="w-full px-3 py-2 bg-slate-900/50 border border-slate-600 rounded-lg text-sm text-white placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-yellow-500"
                                        />
                                    </div>

                                    <div>
                                        <label className="block text-xs text-slate-400 mb-1">API Key</label>
                                        <input
                                            type="password"
                                            value={config.methodologyLlmApiKey}
                                            onChange={e => updateConfig({ methodologyLlmApiKey: e.target.value })}
                                            placeholder="Enter API key..."
                                            className="w-full px-3 py-2 bg-slate-900/50 border border-slate-600 rounded-lg text-sm text-white placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-yellow-500"
                                            autoComplete="new-password"
                                            autoCorrect="off"
                                            autoCapitalize="off"
                                            spellCheck={false}
                                            data-lpignore="true"
                                            data-form-type="other"
                                            data-1p-ignore="true"
                                            name={`panel-methodology-credential-${Date.now()}`}
                                        />
                                    </div>

                                    <div>
                                        <label className="block text-xs text-slate-400 mb-1">Base URL (Optional)</label>
                                        <input
                                            type="text"
                                            value={config.methodologyLlmBaseUrl || ""}
                                            onChange={e => updateConfig({ methodologyLlmBaseUrl: e.target.value })}
                                            placeholder="Custom API base URL..."
                                            className="w-full px-3 py-2 bg-slate-900/50 border border-slate-600 rounded-lg text-sm text-white placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-yellow-500"
                                        />
                                    </div>
                                </>
                            )}
                        </div>
                    </CollapsibleSection>
                )}

                {/* LLM Configuration */}
                <CollapsibleSection
                    title="Layout Generation LLM"
                    icon={<Cpu className="h-4 w-4 text-cyan-400" />}
                    defaultOpen={false}
                >
                    <div className="space-y-3">
                        <div>
                            <label className="block text-xs text-slate-400 mb-1">Provider</label>
                            <div className="w-full px-3 py-2 bg-slate-800/50 border border-slate-600 rounded-lg text-sm text-white">
                                BianXie
                            </div>
                        </div>

                        <div>
                            <label className="block text-xs text-slate-400 mb-1">Model</label>
                            <input
                                type="text"
                                value={config.model}
                                onChange={e => updateConfig({ model: e.target.value })}
                                placeholder="Enter model name (e.g., gemini-2.5-pro)"
                                className="w-full px-3 py-2 bg-slate-900/50 border border-slate-600 rounded-lg text-sm text-white placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-purple-500"
                            />
                            <p className="mt-1 text-xs text-slate-500">
                                Examples: gemini-2.5-pro, gemini-2.5-flash
                            </p>
                        </div>

                        <div>
                            <label className="block text-xs text-slate-400 mb-1">API Key</label>
                            <input
                                type="password"
                                value={config.apiKey}
                                onChange={e => updateConfig({ apiKey: e.target.value })}
                                placeholder="Enter API key..."
                                className="w-full px-3 py-2 bg-slate-900/50 border border-slate-600 rounded-lg text-sm text-white placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-purple-500"
                                autoComplete="new-password"
                                autoCorrect="off"
                                autoCapitalize="off"
                                spellCheck={false}
                                data-lpignore="true"
                                data-form-type="other"
                                data-1p-ignore="true"
                                name={`panel-layout-credential-${Date.now()}`}
                            />
                        </div>

                        <div>
                            <label className="block text-xs text-slate-400 mb-1">Base URL (Optional)</label>
                            <input
                                type="text"
                                value={config.baseUrl || ""}
                                onChange={e => updateConfig({ baseUrl: e.target.value })}
                                placeholder="Custom API base URL..."
                                className="w-full px-3 py-2 bg-slate-900/50 border border-slate-600 rounded-lg text-sm text-white placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-purple-500"
                            />
                        </div>
                    </div>
                </CollapsibleSection>

                {/* Art Style (Preview) */}
                <CollapsibleSection
                    title="Art Style (for Beautification)"
                    icon={<Palette className="h-4 w-4 text-pink-400" />}
                    defaultOpen={false}
                >
                    <textarea
                        value={config.artStyle}
                        onChange={e => updateConfig({ artStyle: e.target.value })}
                        placeholder=""
                        className="w-full h-24 px-3 py-2 bg-slate-900/50 border border-slate-600 rounded-lg text-sm text-white placeholder-slate-500 resize-vertical focus:outline-none focus:ring-2 focus:ring-purple-500"
                    />
                </CollapsibleSection>
            </div>

            {/* Start Button */}
            <div className="p-4 border-t border-slate-700/50 bg-slate-800/80">
                <button
                    onClick={handleStart}
                    disabled={isGenerating || isPdfProcessing || !inputText.trim() || !!session}
                    className="w-full flex items-center justify-center gap-2 py-3 bg-gradient-to-r from-purple-600 to-pink-600 text-white font-medium rounded-xl hover:from-purple-500 hover:to-pink-500 disabled:opacity-50 disabled:cursor-not-allowed transition-all shadow-lg shadow-purple-500/25"
                >
                    {isPdfProcessing ? (
                        <>
                            <div className="w-5 h-5 border-2 border-white border-t-transparent rounded-full animate-spin" />
                            Processing PDF...
                        </>
                    ) : isGenerating ? (
                        <>
                            <div className="w-5 h-5 border-2 border-white border-t-transparent rounded-full animate-spin" />
                            Generating...
                        </>
                    ) : session ? (
                        <>Session Active</>
                    ) : (
                        <>
                            <Play className="h-5 w-5" />
                            Start Generation
                        </>
                    )}
                </button>
            </div>
        </div>
    )
}
