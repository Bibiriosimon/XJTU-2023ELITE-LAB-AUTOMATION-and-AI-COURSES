"use client"

import { useState } from "react"
import {
    ChevronLeft,
    ChevronRight,
    MessageSquare,
    Play,
    Check,
    AlertCircle,
    TrendingUp,
} from "lucide-react"
import { useAutoFigure } from "@/contexts/autofigure-context"

interface IterationControlsProps {
    onContinue: (feedback?: string, score?: number) => void
    onFinalize: () => void
    onLoadIteration: (xml: string) => void
}

export default function IterationControls({
    onContinue,
    onFinalize,
    onLoadIteration,
}: IterationControlsProps) {
    const {
        session,
        isGenerating,
        currentIterationIndex,
        setCurrentIterationIndex,
        getCurrentIteration,
        continueIteration,
        currentXml,
    } = useAutoFigure()

    const [showFeedback, setShowFeedback] = useState(false)
    const [feedback, setFeedback] = useState("")
    const [score, setScore] = useState<number | undefined>(undefined)

    if (!session) return null

    const currentIteration = getCurrentIteration()
    const totalIterations = session.iterations.length
    const maxIterations = session.config.maxIterations

    const handlePrevious = () => {
        if (currentIterationIndex > 0) {
            const newIndex = currentIterationIndex - 1
            setCurrentIterationIndex(newIndex)
            const iteration = session.iterations[newIndex]
            if (iteration) {
                onLoadIteration(iteration.xml)
            }
        }
    }

    const handleNext = () => {
        if (currentIterationIndex < totalIterations - 1) {
            const newIndex = currentIterationIndex + 1
            setCurrentIterationIndex(newIndex)
            const iteration = session.iterations[newIndex]
            if (iteration) {
                onLoadIteration(iteration.xml)
            }
        }
    }

    const handleContinueWithFeedback = async () => {
        // Use onContinue callback which will get current XML from canvas
        // and pass feedback/score to the parent component
        await onContinue(feedback || undefined, score)
        setFeedback("")
        setScore(undefined)
        setShowFeedback(false)
    }

    const qualityReached = currentIteration?.evaluation?.overall_quality &&
        currentIteration.evaluation.overall_quality >= session.config.qualityThreshold

    return (
        <div className="bg-slate-800/90 backdrop-blur-sm border-t border-slate-700/50 p-3">
            {/* Progress Bar */}
            <div className="flex items-center gap-3 mb-3">
                <div className="flex-1">
                    <div className="flex items-center justify-between text-xs text-slate-400 mb-1">
                        <span>Iteration {currentIterationIndex + 1} of {totalIterations}</span>
                        <span>Max: {maxIterations}</span>
                    </div>
                    <div className="h-2 bg-slate-700 rounded-full overflow-hidden">
                        <div
                            className="h-full bg-gradient-to-r from-purple-500 to-pink-500 transition-all duration-300"
                            style={{ width: `${(totalIterations / maxIterations) * 100}%` }}
                        />
                    </div>
                </div>
            </div>

            {/* Evaluation Scores */}
            {currentIteration?.evaluation && (
                <div className="mb-3 p-3 bg-slate-900/50 rounded-lg border border-slate-700/50">
                    <div className="flex items-center gap-2 mb-2">
                        <TrendingUp className="h-4 w-4 text-green-400" />
                        <span className="text-sm font-medium text-white">
                            Quality: {currentIteration.evaluation.overall_quality.toFixed(1)}/10
                        </span>
                        {qualityReached && (
                            <span className="ml-auto px-2 py-0.5 bg-green-500/20 text-green-400 text-xs rounded">
                                Threshold Reached
                            </span>
                        )}
                    </div>

                    <div className="grid grid-cols-3 gap-2 text-xs">
                        <div>
                            <div className="text-slate-500 mb-1">Aesthetic</div>
                            <div className="h-1.5 bg-slate-700 rounded-full overflow-hidden">
                                <div
                                    className="h-full bg-blue-500"
                                    style={{ width: `${(currentIteration.evaluation.scores.aesthetic_design / 10) * 100}%` }}
                                />
                            </div>
                            <div className="text-slate-400 mt-0.5">
                                {currentIteration.evaluation.scores.aesthetic_design}/10
                            </div>
                        </div>
                        <div>
                            <div className="text-slate-500 mb-1">Content</div>
                            <div className="h-1.5 bg-slate-700 rounded-full overflow-hidden">
                                <div
                                    className="h-full bg-green-500"
                                    style={{ width: `${(currentIteration.evaluation.scores.content_fidelity / 10) * 100}%` }}
                                />
                            </div>
                            <div className="text-slate-400 mt-0.5">
                                {currentIteration.evaluation.scores.content_fidelity}/10
                            </div>
                        </div>
                        <div>
                            <div className="text-slate-500 mb-1">Placeholder</div>
                            <div className="h-1.5 bg-slate-700 rounded-full overflow-hidden">
                                <div
                                    className="h-full bg-purple-500"
                                    style={{ width: `${(currentIteration.evaluation.scores.placeholder_usage / 10) * 100}%` }}
                                />
                            </div>
                            <div className="text-slate-400 mt-0.5">
                                {currentIteration.evaluation.scores.placeholder_usage}/10
                            </div>
                        </div>
                    </div>

                    {/* Issues */}
                    {currentIteration.evaluation.specific_issues.length > 0 && (
                        <div className="mt-2 pt-2 border-t border-slate-700/50">
                            <div className="flex items-center gap-1 text-xs text-amber-400 mb-1">
                                <AlertCircle className="h-3 w-3" />
                                Issues Found
                            </div>
                            <ul className="text-xs text-slate-400 space-y-0.5">
                                {currentIteration.evaluation.specific_issues.slice(0, 3).map((issue, i) => (
                                    <li key={i} className="truncate">• {issue}</li>
                                ))}
                                {currentIteration.evaluation.specific_issues.length > 3 && (
                                    <li className="text-slate-500">
                                        +{currentIteration.evaluation.specific_issues.length - 3} more
                                    </li>
                                )}
                            </ul>
                        </div>
                    )}
                </div>
            )}

            {/* Feedback Input */}
            {showFeedback && (
                <div className="mb-3 p-3 bg-slate-900/50 rounded-lg border border-purple-500/30">
                    <div className="flex items-center gap-2 mb-2">
                        <MessageSquare className="h-4 w-4 text-purple-400" />
                        <span className="text-sm font-medium text-white">Add Feedback</span>
                    </div>
                    <textarea
                        value={feedback}
                        onChange={e => setFeedback(e.target.value)}
                        placeholder="Describe what should be improved..."
                        className="w-full h-20 px-3 py-2 bg-slate-800 border border-slate-600 rounded-lg text-sm text-white placeholder-slate-500 resize-none focus:outline-none focus:ring-2 focus:ring-purple-500"
                    />
                    <div className="flex items-center gap-3 mt-2">
                        <label className="text-xs text-slate-400">Your Score (optional):</label>
                        <input
                            type="number"
                            min="0"
                            max="10"
                            step="0.5"
                            value={score || ""}
                            onChange={e => setScore(e.target.value ? Number(e.target.value) : undefined)}
                            placeholder="0-10"
                            className="w-20 px-2 py-1 bg-slate-800 border border-slate-600 rounded text-sm text-white focus:outline-none focus:ring-2 focus:ring-purple-500"
                        />
                    </div>
                </div>
            )}

            {/* Navigation and Action Buttons */}
            <div className="flex items-center gap-2">
                {/* Iteration Navigation */}
                <div className="flex items-center gap-1">
                    <button
                        onClick={handlePrevious}
                        disabled={currentIterationIndex === 0}
                        className="p-2 rounded-lg bg-slate-700/50 text-slate-400 hover:bg-slate-700 hover:text-white disabled:opacity-50 disabled:cursor-not-allowed transition-all"
                    >
                        <ChevronLeft className="h-4 w-4" />
                    </button>
                    <button
                        onClick={handleNext}
                        disabled={currentIterationIndex >= totalIterations - 1}
                        className="p-2 rounded-lg bg-slate-700/50 text-slate-400 hover:bg-slate-700 hover:text-white disabled:opacity-50 disabled:cursor-not-allowed transition-all"
                    >
                        <ChevronRight className="h-4 w-4" />
                    </button>
                </div>

                <div className="flex-1" />

                {/* Action Buttons */}
                <button
                    onClick={() => setShowFeedback(!showFeedback)}
                    className={`flex items-center gap-1.5 px-3 py-2 rounded-lg text-sm transition-all ${
                        showFeedback
                            ? "bg-purple-600/20 text-purple-300 border border-purple-500/50"
                            : "bg-slate-700/50 text-slate-300 hover:bg-slate-700"
                    }`}
                >
                    <MessageSquare className="h-4 w-4" />
                    Feedback
                </button>

                <button
                    onClick={showFeedback ? handleContinueWithFeedback : () => onContinue()}
                    disabled={isGenerating || totalIterations >= maxIterations}
                    className="flex items-center gap-1.5 px-4 py-2 bg-blue-600 text-white rounded-lg text-sm font-medium hover:bg-blue-500 disabled:opacity-50 disabled:cursor-not-allowed transition-all"
                >
                    {isGenerating ? (
                        <>
                            <div className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" />
                            Processing
                        </>
                    ) : (
                        <>
                            <Play className="h-4 w-4" />
                            Continue
                        </>
                    )}
                </button>

                <button
                    onClick={onFinalize}
                    disabled={isGenerating}
                    className="flex items-center gap-1.5 px-4 py-2 bg-gradient-to-r from-green-600 to-emerald-600 text-white rounded-lg text-sm font-medium hover:from-green-500 hover:to-emerald-500 disabled:opacity-50 disabled:cursor-not-allowed transition-all"
                >
                    <Check className="h-4 w-4" />
                    Finalize
                </button>
            </div>
        </div>
    )
}
