import Foundation

public enum LaunchMode: Equatable {
    case summary
    case studyGuide
}

public struct PromptBuilder {
    public init() {}

    public func buildPrompt(paper: Paper, mode: LaunchMode) -> String {
        switch mode {
        case .summary:
            return buildSummaryPrompt(paper: paper)
        case .studyGuide:
            return buildStudyGuidePrompt(paper: paper)
        }
    }

    public func buildSummaryPrompt(paper: Paper) -> String {
        """
        Paper ID: \(paper.id)
        Paper title: \(paper.title)
        Source: \(sourceDescription(for: paper))

        Please help me understand this paper's method clearly.

        Read the attached paper or paper URL and write a neutral, method-focused explanation. Aim for a response that would let me present the method clearly in a PhD reading group. Build the explanation idea by idea, connecting the intuition to the math as each piece is introduced.

        Do not write a paper review or sales pitch. Do not include a “why I should care” section. Include results only when they are surprising, negative, or needed to understand how the method works.

        Use this exact output wrapper:

        [BEGIN PAPER SUMMARY: \(paper.id)]

        # Problem / Motivation

        Explain the problem the paper is solving and the limitation or gap in prior work that motivates the method. Keep this focused on the setup needed to understand the method.

        # High-Level Goal of the Method

        Explain what the method is trying to achieve at a conceptual level. Describe the main object being learned, optimized, inferred, estimated, or constructed.

        # Method Walkthrough

        Explain the method in the order that makes it easiest to understand, building it up idea by idea. For each important idea, first give the intuition, then introduce the corresponding mathematical object, equation, loss, algorithmic step, theorem statement, or assumption when it becomes relevant. Break down the central mechanism, inputs and outputs, training or inference procedure, objectives, assumptions, and any algorithmic steps. Use subsections, bullets, equations, or pseudocode as needed for the paper.

        Important instructions:
        - Introduce notation, equations, losses, algorithms, theorem statements, or assumptions inline exactly when they become relevant.
        - Include both the intuitive reason for each component and the mathematical/formal version of that component.
        - Do not put math in a separate “key math” section unless the paper itself requires that structure.
        - Explain what each mathematical term is doing conceptually.
        - Prefer clear sectioned text or bullets over dense paragraphs.
        - Let the length and structure fit the paper's complexity; do not force a fixed number of bullets or examples.
        - Do not be opinionated.
        - Do not critique the paper except to clarify assumptions required by the method.
        - Mention results only if they are surprising, negative, or necessary to understand the method.

        # Important Assumptions

        List the assumptions needed for the method to make sense. Include modeling assumptions, data assumptions, theoretical assumptions, and experimental setup assumptions only when they affect the method.

        # Reading Group Explanation

        Give a compact set of presentation bullets that would let me explain the method clearly to a PhD reading group. Use as many bullets as the paper needs, but keep each one focused on the core method, how it works, what assumptions it relies on, or what someone should remember.

        [END PAPER SUMMARY: \(paper.id)]
        """
    }

    public func buildStudyGuidePrompt(paper: Paper) -> String {
        """
        Paper ID: \(paper.id)
        Paper title: \(paper.title)
        Source: \(sourceDescription(for: paper))

        Please help me study this paper in depth.

        Read the attached paper or paper URL and create a detailed study guide. Aim for a response that helps me understand the paper deeply enough to discuss it, ask informed questions, and present the method to a PhD reading group. Build the explanation idea by idea, connecting the intuition to the math as each piece is introduced.

        Use web search if needed to identify important preceding work, background concepts, or follow-up work. Do not overdo the literature review; include only context that materially helps understand this paper.

        Do not write a generic review or sales pitch. Do not include a “why I should care” section. Include results only when they are surprising, negative, or needed to understand how the method works.

        Use this exact output wrapper:

        [BEGIN STUDY GUIDE: \(paper.id)]

        # Paper Overview

        Briefly explain the problem, the method family, and what the paper is trying to accomplish.

        # Background Needed

        Explain the prerequisite concepts, notation, mathematical tools, or prior methods needed to understand the paper. Keep this focused and useful.

        # Research Context

        Explain the immediate research context:
        - important preceding work
        - closely related work
        - follow-up work only if useful
        - how this paper fits into its methodological lineage

        # Method Walkthrough

        Explain the method in the order that makes it easiest to understand, building it up idea by idea. Use the paper's section order when it helps, but prioritize conceptual clarity. For each important idea, first give the intuition, then introduce the corresponding mathematical object, equation, loss, algorithmic step, theorem statement, or assumption when it becomes relevant. Break down the central mechanism, inputs and outputs, training or inference procedure, objectives, assumptions, and any algorithmic steps. Use subsections, bullets, equations, or pseudocode as needed for the paper.

        Important instructions:
        - Introduce notation, equations, losses, algorithms, theorem statements, or assumptions inline exactly when they become relevant.
        - Include both the intuitive reason for each component and the mathematical/formal version of that component.
        - Do not put math in a separate “key math” section unless the paper itself requires that structure.
        - Explain what each mathematical term is doing conceptually.
        - Prefer clear sectioned text or bullets over dense paragraphs.
        - Let the length and structure fit the paper's complexity; do not force a fixed number of bullets or examples.
        - Do not be opinionated.
        - Do not critique the paper except to clarify assumptions required by the method.
        - Mention results only if they are surprising, negative, or necessary to understand the method.

        # Experiments and Figures Needed to Understand the Method

        Only include experimental results, figures, tables, or ablations when they clarify how the method works or reveal something surprising/negative.

        # Important Assumptions

        List the assumptions needed for the method to make sense. Include modeling assumptions, data assumptions, theoretical assumptions, and experimental setup assumptions only when they affect the method.

        # Reading Group Presentation Plan

        Give:
        - a 5-minute explanation plan
        - a 15-minute explanation plan
        - suggested slides or whiteboard structure
        - likely questions a PhD reading group might ask

        # What I Should Understand Before Claiming I Understand This Paper

        List the specific concepts, equations, algorithmic steps, or assumptions that I should be able to explain back.

        [END STUDY GUIDE: \(paper.id)]
        """
    }

    public func sourceDescription(for paper: Paper) -> String {
        if let sourceURL = paper.sourceURL, !sourceURL.isEmpty {
            return sourceURL
        }

        if paper.localPDFPath != nil {
            return "Attached local PDF. If no PDF is attached, ask me to attach it before proceeding."
        }

        return "No source URL or local PDF is available. Ask me to provide the paper before proceeding."
    }
}
