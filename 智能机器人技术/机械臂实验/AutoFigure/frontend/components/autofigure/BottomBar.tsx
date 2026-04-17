"use client"

import { useState, useRef, useEffect } from "react"
import {
    Play,
    Paperclip,
    ChevronDown,
    FileText,
    BookOpen,
    PenTool,
    GraduationCap,
    Settings2,
    Check,
} from "lucide-react"
import { useAutoFigure } from "@/contexts/autofigure-context"
import type { ContentType } from "@/lib/autofigure-types"
import { convertPdfToMarkdown } from "@/app/actions/pdf-actions"
import { extractPdfText } from "@/lib/pdf-utils"

interface BottomBarProps {
    onStart: () => void
    onOpenSettings: () => void
}

const contentTypes: { value: ContentType; label: string; icon: React.ReactNode }[] = [
    { value: "paper", label: "Paper", icon: <FileText className="w-4 h-4" /> },
    { value: "survey", label: "Survey", icon: <BookOpen className="w-4 h-4" /> },
    { value: "blog", label: "Blog", icon: <PenTool className="w-4 h-4" /> },
    { value: "textbook", label: "Textbook", icon: <GraduationCap className="w-4 h-4" /> },
]

export default function BottomBar({ onStart, onOpenSettings }: BottomBarProps) {
    const { config, updateConfig, isGenerating, session } = useAutoFigure()
    const [inputText, setInputText] = useState("")
    const [showDropdown, setShowDropdown] = useState(false)
    const [uploadedFile, setUploadedFile] = useState<File | null>(null)
    const dropdownRef = useRef<HTMLDivElement>(null)
    const fileInputRef = useRef<HTMLInputElement>(null)

    // Close dropdown when clicking outside
    useEffect(() => {
        const handleClickOutside = (e: MouseEvent) => {
            if (dropdownRef.current && !dropdownRef.current.contains(e.target as Node)) {
                setShowDropdown(false)
            }
        }
        document.addEventListener("mousedown", handleClickOutside)
        return () => document.removeEventListener("mousedown", handleClickOutside)
    }, [])

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

    const handleKeyDown = (e: React.KeyboardEvent) => {
        if ((e.ctrlKey || e.metaKey) && e.key === "Enter") {
            e.preventDefault()
            handleStart()
        }
    }

    const currentContentType = contentTypes.find(t => t.value === config.contentType) || contentTypes[0]

    return (
        <div className="af-bottom-bar">
            {/* Content Type Dropdown */}
            <div className="af-content-type-select af-dropdown" ref={dropdownRef}>
                <button
                    className="af-content-type-btn"
                    onClick={() => setShowDropdown(!showDropdown)}
                >
                    {currentContentType.icon}
                    <span className="hidden sm:inline">{currentContentType.label}</span>
                    <ChevronDown className={`w-4 h-4 transition-transform ${showDropdown ? 'rotate-180' : ''}`} />
                </button>

                <div className={`af-dropdown-menu ${showDropdown ? 'open' : ''}`}>
                    {contentTypes.map(type => (
                        <div
                            key={type.value}
                            className={`af-dropdown-item ${config.contentType === type.value ? 'active' : ''}`}
                            onClick={() => {
                                updateConfig({ contentType: type.value })
                                setShowDropdown(false)
                            }}
                        >
                            {type.icon}
                            {type.label}
                            {config.contentType === type.value && (
                                <Check className="w-4 h-4 ml-auto" />
                            )}
                        </div>
                    ))}
                </div>
            </div>

            {/* Input Field */}
            <div className="af-input-wrapper">
                <textarea
                    className="af-input-field"
                    value={inputText}
                    onChange={e => setInputText(e.target.value)}
                    onKeyDown={handleKeyDown}
                    placeholder={uploadedFile ? uploadedFile.name : "Paste your content here or upload a file..."}
                    rows={1}
                    disabled={isGenerating || !!session}
                />
                <input
                    ref={fileInputRef}
                    type="file"
                    accept=".pdf,.txt,.md,.tex"
                    onChange={handleFileUpload}
                    className="hidden"
                />
                <button
                    className="af-upload-btn"
                    onClick={() => fileInputRef.current?.click()}
                    title="Upload file"
                    disabled={isGenerating || !!session}
                >
                    <Paperclip className="w-4 h-4" />
                </button>
            </div>

            {/* Generate Button */}
            <button
                className="af-generate-btn"
                onClick={handleStart}
                disabled={isGenerating || isPdfProcessing || !inputText.trim() || !!session}
            >
                {isPdfProcessing ? (
                    <>
                        <div className="spinner" />
                        <span className="hidden sm:inline">Processing PDF...</span>
                    </>
                ) : isGenerating ? (
                    <>
                        <div className="spinner" />
                        <span className="hidden sm:inline">Generating...</span>
                    </>
                ) : session ? (
                    <span>Session Active</span>
                ) : (
                    <>
                        <Play className="w-4 h-4" />
                        <span className="hidden sm:inline">Generate</span>
                    </>
                )}
            </button>

            {/* Settings Button */}
            <button
                className="af-settings-btn"
                onClick={onOpenSettings}
                title="Settings"
            >
                <Settings2 className="w-5 h-5" />
            </button>
        </div>
    )
}
