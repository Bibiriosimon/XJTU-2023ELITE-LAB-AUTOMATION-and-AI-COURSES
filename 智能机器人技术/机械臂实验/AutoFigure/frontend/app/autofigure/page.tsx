"use client"

import { useState, useRef, useEffect } from "react"
import { useRouter } from "next/navigation"
import {
    Sparkles,
    Paperclip,
    ChevronDown,
    FileText,
    BookOpen,
    PenTool,
    GraduationCap,
    Settings2,
    Check,
    ArrowRight,
    Sun,
    Moon,
} from "lucide-react"
import { AutoFigureProvider, useAutoFigure } from "@/contexts/autofigure-context"
import SettingsModal from "@/components/autofigure/SettingsModal"
import type { ContentType } from "@/lib/autofigure-types"
import { convertPdfToMarkdown } from "@/app/actions/pdf-actions"
import { extractPdfText } from "@/lib/pdf-utils"
import "./autofigure-theme.css"

const contentTypes: { value: ContentType; label: string; icon: React.ReactNode }[] = [
    { value: "paper", label: "Paper", icon: <FileText className="w-4 h-4" /> },
    { value: "survey", label: "Survey", icon: <BookOpen className="w-4 h-4" /> },
    { value: "blog", label: "Blog", icon: <PenTool className="w-4 h-4" /> },
    { value: "textbook", label: "Textbook", icon: <GraduationCap className="w-4 h-4" /> },
]

function AutoFigureStartContent() {
    const router = useRouter()
    const { config, updateConfig } = useAutoFigure()

    const [darkMode, setDarkMode] = useState(false)
    const [inputText, setInputText] = useState("")
    const [showDropdown, setShowDropdown] = useState(false)
    const [showSettings, setShowSettings] = useState(false)
    const [uploadedFile, setUploadedFile] = useState<File | null>(null)
    const [isPdfProcessing, setIsPdfProcessing] = useState(false)

    const dropdownRef = useRef<HTMLDivElement>(null)
    const fileInputRef = useRef<HTMLInputElement>(null)

    // Load dark mode preference
    useEffect(() => {
        const savedDarkMode = localStorage.getItem("autofigure-dark-mode")
        if (savedDarkMode !== null) {
            const isDark = savedDarkMode === "true"
            setDarkMode(isDark)
            document.documentElement.classList.toggle("dark", isDark)
        } else {
            document.documentElement.classList.remove("dark")
        }
    }, [])

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

    // Keyboard shortcut for settings
    useEffect(() => {
        const handleKeyDown = (e: KeyboardEvent) => {
            if ((e.ctrlKey || e.metaKey) && e.key === ",") {
                e.preventDefault()
                setShowSettings(prev => !prev)
            }
        }
        document.addEventListener("keydown", handleKeyDown)
        return () => document.removeEventListener("keydown", handleKeyDown)
    }, [])

    const toggleDarkMode = () => {
        const newValue = !darkMode
        setDarkMode(newValue)
        localStorage.setItem("autofigure-dark-mode", String(newValue))
        document.documentElement.classList.toggle("dark", newValue)
    }

    const handleFileUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
        const file = e.target.files?.[0]
        if (!file) return

        setUploadedFile(file)

        if (file.type === "text/plain" || file.name.endsWith(".md") || file.name.endsWith(".tex")) {
            const text = await file.text()
            setInputText(text)
        } else if (file.type === "application/pdf") {
            setIsPdfProcessing(true)
            setInputText(`[Processing PDF: ${file.name}...]`)

            try {
                const formData = new FormData()
                formData.append("pdf_file", file)

                console.log("[AutoFigure] Trying remote API extraction...")
                const result = await convertPdfToMarkdown(formData)

                if (result.success && result.markdown) {
                    setInputText(result.markdown)
                    console.log("[AutoFigure] PDF extraction successful (remote API)")
                } else {
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

    const isConfigValid = () => {
        if (!config.apiKey.trim()) return false
        if (config.contentType === 'paper' && config.enableMethodologyExtraction) {
            if (!config.methodologyLlmApiKey.trim()) return false
        }
        return true
    }

    const handleGenerate = () => {
        if (!inputText.trim()) return

        // Save input text to config
        const updatedConfig = { ...config, inputText }
        updateConfig({ inputText })

        // Check if config is valid
        if (!isConfigValid()) {
            setShowSettings(true)
            return
        }

        // Persist config to localStorage for cross-page state
        localStorage.setItem('autofigure-pending-config', JSON.stringify(updatedConfig))

        // Navigate to canvas page
        router.push('/autofigure/canvas')
    }

    const handleKeyDown = (e: React.KeyboardEvent) => {
        if ((e.ctrlKey || e.metaKey) && e.key === "Enter") {
            e.preventDefault()
            handleGenerate()
        }
    }

    const currentContentType = contentTypes.find(t => t.value === config.contentType) || contentTypes[0]

    return (
        <div className="af-start-page">
            {/* Header - minimal */}
            <div className="af-start-header">
                <button
                    className="af-icon-btn"
                    onClick={toggleDarkMode}
                    title={darkMode ? "Light Mode" : "Dark Mode"}
                >
                    {darkMode ? <Sun className="w-5 h-5" /> : <Moon className="w-5 h-5" />}
                </button>

                <a
                    href="https://westlakenlp.com/"
                    target="_blank"
                    rel="noopener noreferrer"
                    className="af-external-link"
                >
                    <img src="/westlakenlp.png" alt="WestlakeNLP" className="af-external-link-icon" />
                    <span>WestlakeNLP</span>
                </a>

                <a
                    href="https://github.com/ResearAI"
                    target="_blank"
                    rel="noopener noreferrer"
                    className="af-external-link"
                >
                    <img src="/github.png" alt="GitHub" className="af-external-link-icon" />
                    <span>AutoFigure</span>
                </a>
            </div>

            {/* Centered Content */}
            <div className="af-start-center">
                {/* Logo */}
                <div className="af-start-logo">
                    <div className="af-start-logo-icon">
                        <Sparkles className="w-8 h-8 text-white" />
                    </div>
                    <h1 className="af-start-title">AutoFigure</h1>
                </div>

                {/* Input Card */}
                <div className="af-start-input-card">
                    {/* Content Type Dropdown */}
                    <div className="af-start-dropdown-row">
                        <div className="af-dropdown" ref={dropdownRef}>
                            <button
                                className="af-start-content-type-btn"
                                onClick={() => setShowDropdown(!showDropdown)}
                            >
                                {currentContentType.icon}
                                <span>{currentContentType.label}</span>
                                <ChevronDown className={`w-4 h-4 transition-transform ${showDropdown ? 'rotate-180' : ''}`} />
                            </button>

                            <div className={`af-dropdown-menu af-dropdown-menu-down ${showDropdown ? 'open' : ''}`}>
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
                    </div>

                    {/* Text Input Area */}
                    <div className="af-start-textarea-wrapper">
                        <textarea
                            className="af-start-textarea"
                            value={inputText}
                            onChange={e => setInputText(e.target.value)}
                            onKeyDown={handleKeyDown}
                            placeholder={uploadedFile ? uploadedFile.name : "Paste your content here or upload a file..."}
                            rows={1}
                        />
                    </div>

                    {/* Action Bar */}
                    <div className="af-start-actions">
                        <input
                            ref={fileInputRef}
                            type="file"
                            accept=".pdf,.txt,.md,.tex"
                            onChange={handleFileUpload}
                            className="hidden"
                        />
                        <button
                            className="af-start-action-btn"
                            onClick={() => fileInputRef.current?.click()}
                            title="Upload file"
                            disabled={isPdfProcessing}
                        >
                            <Paperclip className="w-5 h-5" />
                        </button>

                        <button
                            className="af-start-action-btn"
                            onClick={() => setShowSettings(true)}
                            title="Settings (Ctrl+,)"
                        >
                            <Settings2 className="w-5 h-5" />
                        </button>

                        <div className="flex-1" />

                        <button
                            className="af-start-generate-btn"
                            onClick={handleGenerate}
                            disabled={isPdfProcessing || !inputText.trim()}
                            title="Generate (Ctrl+Enter)"
                        >
                            {isPdfProcessing ? (
                                <div className="w-5 h-5 border-2 border-white border-t-transparent rounded-full animate-spin" />
                            ) : (
                                <ArrowRight className="w-5 h-5" />
                            )}
                        </button>
                    </div>
                </div>

            </div>

            {/* Settings Modal */}
            <SettingsModal
                isOpen={showSettings}
                onClose={() => setShowSettings(false)}
            />
        </div>
    )
}

export default function AutoFigureStartPage() {
    return (
        <AutoFigureProvider>
            <AutoFigureStartContent />
        </AutoFigureProvider>
    )
}
