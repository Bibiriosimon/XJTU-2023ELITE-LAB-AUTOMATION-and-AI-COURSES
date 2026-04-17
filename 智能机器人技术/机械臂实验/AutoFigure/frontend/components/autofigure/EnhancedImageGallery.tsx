"use client"

import { useState, useRef, useEffect } from "react"
import {
    X,
    Download,
    ZoomIn,
    ZoomOut,
    ChevronLeft,
    ChevronRight,
    Check,
    Loader2,
    AlertCircle,
    Image as ImageIcon,
    Sparkles,
} from "lucide-react"
import { useAutoFigure } from "@/contexts/autofigure-context"
import type { EnhancedImage } from "@/lib/autofigure-types"

interface EnhancedImageGalleryProps {
    isOpen: boolean
    onClose: () => void
    onSelect?: (image: EnhancedImage) => void
}

export default function EnhancedImageGallery({
    isOpen,
    onClose,
    onSelect,
}: EnhancedImageGalleryProps) {
    const { enhancedImages, enhancementProgress, isGenerating } = useAutoFigure()
    const [selectedIndex, setSelectedIndex] = useState(0)
    const [zoom, setZoom] = useState(1)
    const carouselRef = useRef<HTMLDivElement>(null)

    // Scroll selected card into view
    useEffect(() => {
        if (carouselRef.current) {
            const cards = carouselRef.current.children
            if (cards[selectedIndex]) {
                (cards[selectedIndex] as HTMLElement).scrollIntoView({
                    behavior: 'smooth',
                    block: 'nearest',
                    inline: 'center',
                })
            }
        }
    }, [selectedIndex])

    if (!isOpen) return null

    const selectedImage = enhancedImages[selectedIndex]

    const handlePrevious = () => {
        setSelectedIndex(prev => Math.max(0, prev - 1))
        setZoom(1)
    }

    const handleNext = () => {
        setSelectedIndex(prev => Math.min(enhancedImages.length - 1, prev + 1))
        setZoom(1)
    }

    const handleZoomIn = () => {
        setZoom(prev => Math.min(3, prev + 0.25))
    }

    const handleZoomOut = () => {
        setZoom(prev => Math.max(0.5, prev - 0.25))
    }

    const handleDownload = () => {
        if (!selectedImage?.pngBase64) return
        const link = document.createElement("a")
        link.href = `data:image/png;base64,${selectedImage.pngBase64}`
        link.download = `autofigure_polished_v${selectedImage.variant}.png`
        link.click()
    }

    const handleSelect = () => {
        if (selectedImage && onSelect) {
            onSelect(selectedImage)
            onClose()
        }
    }

    const getStatusIcon = (status: EnhancedImage["status"]) => {
        switch (status) {
            case "pending":
                return <div className="w-3 h-3 rounded-full" style={{ background: 'var(--af-text-muted)' }} />
            case "processing":
                return <Loader2 className="w-3 h-3 animate-spin" style={{ color: 'var(--af-accent-primary)' }} />
            case "completed":
                return <Check className="w-3 h-3" style={{ color: '#22c55e' }} />
            case "failed":
                return <AlertCircle className="w-3 h-3" style={{ color: '#ef4444' }} />
        }
    }

    // Handle keyboard navigation
    const handleKeyDown = (e: React.KeyboardEvent) => {
        if (e.key === 'ArrowLeft') handlePrevious()
        else if (e.key === 'ArrowRight') handleNext()
        else if (e.key === 'Escape') onClose()
    }

    return (
        <div
            className="fixed inset-0 z-50 flex items-center justify-center"
            onKeyDown={handleKeyDown}
            tabIndex={0}
        >
            {/* Backdrop */}
            <div
                className="absolute inset-0 backdrop-blur-md"
                style={{ background: 'rgba(15, 23, 42, 0.6)' }}
                onClick={onClose}
            />

            {/* Gallery - Horizontal Layout */}
            <div
                className="relative w-full max-w-7xl h-[75vh] mx-4 rounded-2xl shadow-2xl overflow-hidden flex flex-col"
                style={{
                    background: 'var(--af-bg-elevated)',
                    border: '1px solid var(--af-border-primary)',
                }}
            >
                {/* Compact Header */}
                <div
                    className="flex items-center justify-between px-5 py-3"
                    style={{
                        borderBottom: '1px solid var(--af-border-primary)',
                        background: 'linear-gradient(135deg, rgba(14, 165, 233, 0.08) 0%, rgba(56, 189, 248, 0.03) 100%)',
                    }}
                >
                    <div className="flex items-center gap-3">
                        <div
                            className="p-1.5 rounded-lg"
                            style={{
                                background: 'linear-gradient(135deg, var(--af-accent-primary) 0%, var(--af-accent-secondary) 100%)',
                            }}
                        >
                            <Sparkles className="h-4 w-4 text-white" />
                        </div>
                        <div>
                            <h2 className="text-base font-semibold" style={{ color: 'var(--af-text-primary)' }}>
                                Polished Images
                            </h2>
                        </div>

                        {/* Progress indicator */}
                        {isGenerating && (
                            <div className="flex items-center gap-2 ml-4">
                                <div
                                    className="w-24 h-1.5 rounded-full overflow-hidden"
                                    style={{ background: 'var(--af-bg-tertiary)' }}
                                >
                                    <div
                                        className="h-full transition-all duration-300"
                                        style={{
                                            width: `${enhancementProgress}%`,
                                            background: 'linear-gradient(90deg, var(--af-accent-primary), var(--af-accent-secondary))',
                                        }}
                                    />
                                </div>
                                <span className="text-xs" style={{ color: 'var(--af-text-tertiary)' }}>
                                    {enhancementProgress}%
                                </span>
                            </div>
                        )}

                        {!isGenerating && (
                            <span className="text-sm ml-2" style={{ color: 'var(--af-text-tertiary)' }}>
                                {enhancedImages.filter(img => img.status === 'completed').length} of {enhancedImages.length} completed
                            </span>
                        )}
                    </div>

                    {/* Right side controls */}
                    <div className="flex items-center gap-2">
                        {/* Zoom Controls */}
                        <div className="flex items-center gap-1 mr-2">
                            <button
                                onClick={handleZoomOut}
                                disabled={zoom <= 0.5}
                                className="af-icon-btn"
                                style={{
                                    width: '28px',
                                    height: '28px',
                                    opacity: zoom <= 0.5 ? 0.5 : 1,
                                }}
                            >
                                <ZoomOut className="h-3.5 w-3.5" />
                            </button>
                            <span
                                className="text-xs w-10 text-center"
                                style={{ color: 'var(--af-text-secondary)' }}
                            >
                                {Math.round(zoom * 100)}%
                            </span>
                            <button
                                onClick={handleZoomIn}
                                disabled={zoom >= 3}
                                className="af-icon-btn"
                                style={{
                                    width: '28px',
                                    height: '28px',
                                    opacity: zoom >= 3 ? 0.5 : 1,
                                }}
                            >
                                <ZoomIn className="h-3.5 w-3.5" />
                            </button>
                        </div>

                        <button
                            onClick={handleDownload}
                            disabled={!selectedImage?.pngBase64}
                            className="af-btn-secondary flex items-center gap-1.5 px-3 py-1.5 text-sm"
                            style={{ opacity: !selectedImage?.pngBase64 ? 0.5 : 1 }}
                        >
                            <Download className="h-3.5 w-3.5" />
                            Download
                        </button>

                        {onSelect && (
                            <button
                                onClick={handleSelect}
                                disabled={!selectedImage?.pngBase64}
                                className="af-btn-primary flex items-center gap-1.5 px-3 py-1.5 text-sm"
                                style={{ opacity: !selectedImage?.pngBase64 ? 0.5 : 1 }}
                            >
                                <Check className="h-3.5 w-3.5" />
                                Select
                            </button>
                        )}

                        <button
                            onClick={onClose}
                            className="af-icon-btn ml-2"
                            style={{ width: '32px', height: '32px' }}
                        >
                            <X className="h-4 w-4" />
                        </button>
                    </div>
                </div>

                {/* Main Image Area */}
                <div className="flex-1 relative overflow-hidden" style={{ background: 'var(--af-bg-tertiary)' }}>
                    {selectedImage?.pngBase64 ? (
                        <div className="absolute inset-0 flex items-center justify-center p-6 overflow-auto">
                            <img
                                src={`data:image/png;base64,${selectedImage.pngBase64}`}
                                alt={`Polished variant ${selectedImage.variant}`}
                                className="max-w-full max-h-full object-contain rounded-lg transition-transform duration-200"
                                style={{
                                    transform: `scale(${zoom})`,
                                    boxShadow: '0 8px 32px rgba(0, 0, 0, 0.3)',
                                }}
                            />
                        </div>
                    ) : selectedImage?.status === "processing" ? (
                        <div className="absolute inset-0 flex flex-col items-center justify-center gap-3">
                            <Loader2 className="w-10 h-10 animate-spin" style={{ color: 'var(--af-accent-primary)' }} />
                            <span style={{ color: 'var(--af-text-tertiary)' }}>
                                Generating variant {selectedImage.variant}...
                            </span>
                        </div>
                    ) : selectedImage?.status === "failed" ? (
                        <div className="absolute inset-0 flex flex-col items-center justify-center gap-3 px-8">
                            <AlertCircle className="w-10 h-10" style={{ color: '#ef4444' }} />
                            <span className="font-medium" style={{ color: '#ef4444' }}>Failed to generate</span>
                            {selectedImage.error && (
                                <p className="text-sm text-center max-w-md" style={{ color: 'var(--af-text-muted)' }}>
                                    {selectedImage.error.includes('insufficient_user_quota')
                                        ? 'API quota exceeded. Please check your account balance.'
                                        : selectedImage.error}
                                </p>
                            )}
                        </div>
                    ) : (
                        <div className="absolute inset-0 flex flex-col items-center justify-center gap-3">
                            <ImageIcon className="w-10 h-10" style={{ color: 'var(--af-text-muted)' }} />
                            <span style={{ color: 'var(--af-text-muted)' }}>No image to display</span>
                        </div>
                    )}

                    {/* Navigation Arrows */}
                    {enhancedImages.length > 1 && (
                        <>
                            <button
                                onClick={handlePrevious}
                                disabled={selectedIndex === 0}
                                className="absolute left-4 top-1/2 -translate-y-1/2 p-2.5 rounded-full transition-all hover:scale-110"
                                style={{
                                    background: 'rgba(255, 255, 255, 0.1)',
                                    backdropFilter: 'blur(8px)',
                                    border: '1px solid rgba(255, 255, 255, 0.2)',
                                    color: 'white',
                                    opacity: selectedIndex === 0 ? 0.3 : 0.8,
                                }}
                            >
                                <ChevronLeft className="h-5 w-5" />
                            </button>
                            <button
                                onClick={handleNext}
                                disabled={selectedIndex >= enhancedImages.length - 1}
                                className="absolute right-4 top-1/2 -translate-y-1/2 p-2.5 rounded-full transition-all hover:scale-110"
                                style={{
                                    background: 'rgba(255, 255, 255, 0.1)',
                                    backdropFilter: 'blur(8px)',
                                    border: '1px solid rgba(255, 255, 255, 0.2)',
                                    color: 'white',
                                    opacity: selectedIndex >= enhancedImages.length - 1 ? 0.3 : 0.8,
                                }}
                            >
                                <ChevronRight className="h-5 w-5" />
                            </button>
                        </>
                    )}

                    {/* Page Indicators */}
                    {enhancedImages.length > 1 && (
                        <div className="absolute bottom-4 left-1/2 -translate-x-1/2 flex items-center gap-1.5">
                            {enhancedImages.map((_, index) => (
                                <button
                                    key={index}
                                    onClick={() => {
                                        setSelectedIndex(index)
                                        setZoom(1)
                                    }}
                                    className="transition-all duration-200"
                                    style={{
                                        width: selectedIndex === index ? '20px' : '8px',
                                        height: '8px',
                                        borderRadius: '4px',
                                        background: selectedIndex === index
                                            ? 'var(--af-accent-primary)'
                                            : 'rgba(255, 255, 255, 0.3)',
                                    }}
                                />
                            ))}
                        </div>
                    )}
                </div>

                {/* Bottom Carousel */}
                <div
                    className="py-3 px-4"
                    style={{
                        borderTop: '1px solid var(--af-border-primary)',
                        background: 'var(--af-bg-glass)',
                    }}
                >
                    <div
                        ref={carouselRef}
                        className="flex gap-3 overflow-x-auto pb-1 scroll-smooth"
                        style={{
                            scrollSnapType: 'x mandatory',
                            scrollbarWidth: 'thin',
                            scrollbarColor: 'var(--af-border-primary) transparent',
                        }}
                    >
                        {enhancedImages.map((image, index) => (
                            <button
                                key={index}
                                onClick={() => {
                                    setSelectedIndex(index)
                                    setZoom(1)
                                }}
                                className="relative flex-shrink-0 rounded-lg overflow-hidden transition-all duration-300"
                                style={{
                                    width: '140px',
                                    aspectRatio: '16/9',
                                    scrollSnapAlign: 'center',
                                    transform: selectedIndex === index ? 'scale(1.05)' : 'scale(0.95)',
                                    opacity: selectedIndex === index ? 1 : 0.6,
                                    border: selectedIndex === index
                                        ? '2px solid var(--af-accent-primary)'
                                        : '2px solid transparent',
                                    boxShadow: selectedIndex === index
                                        ? '0 0 20px rgba(14, 165, 233, 0.4)'
                                        : '0 2px 8px rgba(0, 0, 0, 0.2)',
                                }}
                            >
                                {image.pngBase64 ? (
                                    <img
                                        src={`data:image/png;base64,${image.pngBase64}`}
                                        alt={`Variant ${image.variant}`}
                                        className="w-full h-full object-cover"
                                    />
                                ) : (
                                    <div
                                        className="w-full h-full flex items-center justify-center"
                                        style={{ background: 'var(--af-bg-tertiary)' }}
                                    >
                                        {image.status === 'processing' ? (
                                            <Loader2 className="w-5 h-5 animate-spin" style={{ color: 'var(--af-accent-primary)' }} />
                                        ) : image.status === 'failed' ? (
                                            <AlertCircle className="w-5 h-5" style={{ color: '#ef4444' }} />
                                        ) : (
                                            <ImageIcon className="w-5 h-5" style={{ color: 'var(--af-text-muted)' }} />
                                        )}
                                    </div>
                                )}

                                {/* Status badge */}
                                <div
                                    className="absolute top-1.5 right-1.5 p-1 rounded-full"
                                    style={{ background: 'rgba(0, 0, 0, 0.5)' }}
                                >
                                    {getStatusIcon(image.status)}
                                </div>

                                {/* Variant label */}
                                <div
                                    className="absolute bottom-1.5 left-1.5 px-1.5 py-0.5 rounded text-xs font-medium text-white"
                                    style={{ background: 'rgba(0, 0, 0, 0.6)' }}
                                >
                                    V{image.variant}
                                </div>
                            </button>
                        ))}

                        {/* Loading placeholder when empty */}
                        {enhancedImages.length === 0 && (
                            <div
                                className="flex-shrink-0 rounded-lg flex items-center justify-center"
                                style={{
                                    width: '140px',
                                    aspectRatio: '16/9',
                                    background: 'var(--af-bg-tertiary)',
                                }}
                            >
                                <Loader2 className="w-5 h-5 animate-spin" style={{ color: 'var(--af-text-muted)' }} />
                            </div>
                        )}
                    </div>
                </div>
            </div>
        </div>
    )
}
