"use client"

import { useState, useEffect } from "react"
import { X } from "lucide-react"
import { LLM_PROVIDERS, type LLMProvider } from "@/lib/autofigure-types"

interface ImageGenConfig {
    provider: LLMProvider
    apiKey: string
    model: string
    baseUrl: string
}

interface ImageGenSettingsProps {
    isOpen: boolean
    onClose: () => void
    config: ImageGenConfig
    onSave: (config: ImageGenConfig) => void
}

export default function ImageGenSettings({
    isOpen,
    onClose,
    config,
    onSave,
}: ImageGenSettingsProps) {
    const [localConfig, setLocalConfig] = useState<ImageGenConfig>(config)

    // Sync with parent config when modal opens
    useEffect(() => {
        if (isOpen) {
            setLocalConfig(config)
        }
    }, [isOpen, config])

    if (!isOpen) return null

    const handleSave = () => {
        onSave(localConfig)
    }

    const handleBackdropClick = (e: React.MouseEvent) => {
        if (e.target === e.currentTarget) {
            onClose()
        }
    }

    const handleProviderChange = (provider: LLMProvider) => {
        // Get default base URL based on provider
        let defaultBaseUrl = 'https://api.bianxie.ai/v1/chat/completions'
        if (provider === 'openrouter') {
            defaultBaseUrl = 'https://openrouter.ai/api/v1'
        } else if (provider === 'gemini') {
            defaultBaseUrl = 'https://generativelanguage.googleapis.com/v1beta'
        }

        setLocalConfig(prev => ({
            ...prev,
            provider,
            baseUrl: defaultBaseUrl,
        }))
    }

    const getPlaceholders = () => {
        if (localConfig.provider === 'openrouter') {
            return {
                apiKey: 'Enter your OpenRouter API key',
                model: 'e.g., google/gemini-3-pro-image-preview',
                baseUrl: 'https://openrouter.ai/api/v1',
            }
        }
        if (localConfig.provider === 'gemini') {
            return {
                apiKey: 'Enter your Google AI API key',
                model: 'e.g., gemini-3-pro-image-preview',
                baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
            }
        }
        return {
            apiKey: 'Enter your Bianxie API key',
            model: 'e.g., gemini-3-pro-image-preview',
            baseUrl: 'https://api.bianxie.ai/v1/chat/completions',
        }
    }

    const placeholders = getPlaceholders()

    return (
        <div
            className="fixed inset-0 z-50 flex items-center justify-center"
            style={{ background: 'rgba(0, 0, 0, 0.5)' }}
            onClick={handleBackdropClick}
        >
            <div
                className="af-settings-modal"
                style={{
                    background: 'var(--af-bg-elevated)',
                    backdropFilter: 'blur(12px)',
                    borderRadius: '16px',
                    border: '1px solid var(--af-border-primary)',
                    boxShadow: 'var(--af-shadow-lg)',
                    padding: '24px',
                    width: '400px',
                    maxWidth: 'calc(100% - 32px)',
                }}
            >
                {/* Header */}
                <div className="flex items-center justify-between mb-6">
                    <h3
                        className="text-lg font-semibold"
                        style={{ color: 'var(--af-text-primary)' }}
                    >
                        Image Generation
                    </h3>
                    <button
                        className="af-icon-btn"
                        onClick={onClose}
                        style={{ width: '32px', height: '32px' }}
                    >
                        <X className="w-5 h-5" />
                    </button>
                </div>

                {/* Form */}
                <div className="space-y-4">
                    {/* Provider */}
                    <div>
                        <label
                            className="block text-sm font-medium mb-2"
                            style={{ color: 'var(--af-text-secondary)' }}
                        >
                            Provider
                        </label>
                        <select
                            value={localConfig.provider}
                            onChange={e => handleProviderChange(e.target.value as LLMProvider)}
                            className="af-input"
                            style={{ width: '100%' }}
                        >
                            {Object.entries(LLM_PROVIDERS).map(([key, value]) => (
                                <option key={key} value={key}>
                                    {value.name}
                                </option>
                            ))}
                        </select>
                        <p
                            className="text-xs mt-1"
                            style={{ color: 'var(--af-text-tertiary)' }}
                        >
                            {LLM_PROVIDERS[localConfig.provider]?.description}
                        </p>
                    </div>

                    {/* API Key */}
                    <div>
                        <label
                            className="block text-sm font-medium mb-2"
                            style={{ color: 'var(--af-text-secondary)' }}
                        >
                            API Key
                        </label>
                        <input
                            type="password"
                            value={localConfig.apiKey}
                            onChange={e => setLocalConfig(prev => ({ ...prev, apiKey: e.target.value }))}
                            placeholder={placeholders.apiKey}
                            className="af-input"
                            style={{ width: '100%' }}
                            autoComplete="new-password"
                            autoCorrect="off"
                            autoCapitalize="off"
                            spellCheck={false}
                            data-lpignore="true"
                            data-form-type="other"
                            data-1p-ignore="true"
                            name={`imagegen-credential-${Date.now()}`}
                        />
                    </div>

                    {/* Model */}
                    <div>
                        <label
                            className="block text-sm font-medium mb-2"
                            style={{ color: 'var(--af-text-secondary)' }}
                        >
                            Model
                        </label>
                        <input
                            type="text"
                            value={localConfig.model}
                            onChange={e => setLocalConfig(prev => ({ ...prev, model: e.target.value }))}
                            placeholder={placeholders.model}
                            className="af-input"
                            style={{ width: '100%' }}
                        />
                        <p
                            className="text-xs mt-1"
                            style={{ color: 'var(--af-text-tertiary)' }}
                        >
                            Enter your image generation model name
                        </p>
                    </div>

                    {/* Base URL */}
                    <div>
                        <label
                            className="block text-sm font-medium mb-2"
                            style={{ color: 'var(--af-text-secondary)' }}
                        >
                            Base URL
                        </label>
                        <input
                            type="text"
                            value={localConfig.baseUrl}
                            onChange={e => setLocalConfig(prev => ({ ...prev, baseUrl: e.target.value }))}
                            placeholder={placeholders.baseUrl}
                            className="af-input"
                            style={{ width: '100%' }}
                        />
                    </div>

                </div>

                {/* Actions */}
                <div className="flex justify-end gap-3 mt-6">
                    <button
                        className="af-btn-secondary"
                        onClick={onClose}
                    >
                        Cancel
                    </button>
                    <button
                        className="af-btn-primary"
                        onClick={handleSave}
                        disabled={!localConfig.apiKey.trim() || !localConfig.model.trim() || !localConfig.baseUrl.trim()}
                        style={{ opacity: (localConfig.apiKey.trim() && localConfig.model.trim() && localConfig.baseUrl.trim()) ? 1 : 0.5 }}
                    >
                        Save
                    </button>
                </div>
            </div>
        </div>
    )
}
