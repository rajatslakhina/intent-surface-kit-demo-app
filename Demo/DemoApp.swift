import SwiftUI
import IntentSurfaceKit

// MARK: - Sample domain

struct DemoDocument: Identifiable, Equatable {
    let id: String
    let name: String
    let kind: String
    let synonyms: [String]

    var entity: SurfaceEntity {
        SurfaceEntity(
            id: EntityID(id),
            typeIdentifier: "document",
            displayName: name,
            synonyms: synonyms,
            attributes: ["kind": kind]
        )
    }
}

private let sampleDocuments: [DemoDocument] = [
    DemoDocument(id: "doc-q3", name: "Q3 Planning", kind: "Keynote", synonyms: ["planning deck", "q3 deck"]),
    DemoDocument(id: "doc-budget", name: "Budget 2026", kind: "Numbers", synonyms: ["the budget"]),
    DemoDocument(id: "doc-design", name: "Design Review", kind: "Pages", synonyms: ["design doc"]),
    DemoDocument(id: "doc-notes-a", name: "Meeting Notes Alpha", kind: "Notes", synonyms: []),
    DemoDocument(id: "doc-notes-b", name: "Meeting Notes Beta", kind: "Notes", synonyms: []),
    DemoDocument(id: "doc-roadmap", name: "Roadmap Draft", kind: "Freeform", synonyms: ["the roadmap"])
]

// MARK: - Transcript

struct TranscriptEntry: Identifiable, Equatable {
    enum Role: Equatable {
        case user
        case assistant
        case system
    }

    let id = UUID()
    let role: Role
    let text: String
}

// MARK: - App model

@MainActor
@Observable
final class AppModel {
    var documents: [DemoDocument] = sampleDocuments
    var focusedDocumentID: String?
    var transcript: [TranscriptEntry] = []
    var pendingCandidates: [SurfaceEntity] = []
    var isExecuting = false
    var progressFraction: Double = 0
    var progressMessage = ""

    let tracker = ScreenContextTracker()
    private let surface = IntentSurface()
    private var executionHandle: IntentExecutionHandle?

    func start() async {
        await surface.catalog.register(contentsOf: documents.map { $0.entity })
        transcript.append(TranscriptEntry(
            role: .system,
            text: "Try: “share the third one”, “open the budget”, “summarize this”, “delete meeting notes”."
        ))
    }

    func rowAppeared(_ document: DemoDocument) {
        guard let index = documents.firstIndex(of: document) else { return }
        tracker.setVisible(EntityID(document.id), at: index)
    }

    func rowDisappeared(_ document: DemoDocument) {
        tracker.setHidden(EntityID(document.id))
    }

    func tapped(_ document: DemoDocument) {
        if focusedDocumentID == document.id {
            focusedDocumentID = nil
            tracker.focus(nil)
        } else {
            focusedDocumentID = document.id
            tracker.focus(EntityID(document.id))
        }
    }

    func submit(_ utterance: String) async {
        let trimmed = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        transcript.append(TranscriptEntry(role: .user, text: trimmed))

        let decision = await surface.handle(utterance: trimmed, screen: tracker.snapshot())
        pendingCandidates = []

        switch decision {
        case .perform(let verb, let entity):
            await perform(verb, on: entity)

        case .askToClarify(let prompt, let candidates):
            pendingCandidates = candidates
            transcript.append(TranscriptEntry(role: .assistant, text: prompt))

        case .report(let failure):
            transcript.append(TranscriptEntry(role: .assistant, text: describe(failure)))

        case .notUnderstood:
            transcript.append(TranscriptEntry(
                role: .assistant,
                text: "I didn’t catch a command there. Try “open”, “share”, “delete”, or “summarize”."
            ))

        case .busy:
            transcript.append(TranscriptEntry(
                role: .assistant,
                text: "Still working on the last request — try again in a moment."
            ))
        }
    }

    func pickCandidate(at index: Int) async {
        // The chips are rendered from pendingCandidates, so index is valid
        // for the current array; guard anyway — UI events can race state.
        guard index >= 0, index < pendingCandidates.count else { return }
        await submit("the \(spokenOrdinal(for: index + 1)) one")
    }

    private func perform(_ verb: IntentVerb, on entity: SurfaceEntity) async {
        switch verb {
        case .open:
            transcript.append(TranscriptEntry(role: .assistant, text: "Opening “\(entity.displayName)”."))
        case .share:
            transcript.append(TranscriptEntry(role: .assistant, text: "Sharing “\(entity.displayName)”."))
        case .delete:
            documents.removeAll { $0.id == entity.id.rawValue }
            if focusedDocumentID == entity.id.rawValue {
                focusedDocumentID = nil
            }
            tracker.setHidden(entity.id)
            await surface.catalog.unregister(entity.id)
            transcript.append(TranscriptEntry(role: .assistant, text: "Deleted “\(entity.displayName)”."))
        case .summarize:
            await runStreamingSummary(of: entity)
        }
    }

    private func runStreamingSummary(of entity: SurfaceEntity) async {
        isExecuting = true
        progressFraction = 0
        progressMessage = "Starting…"

        let plan = IntentPlan(title: "Summarize \(entity.displayName)", steps: [
            IntentStep(label: "Reading \(entity.displayName)") {
                try await Task.sleep(nanoseconds: 900_000_000)
            },
            IntentStep(label: "Extracting key points") {
                try await Task.sleep(nanoseconds: 900_000_000)
            },
            IntentStep(label: "Composing summary") {
                try await Task.sleep(nanoseconds: 900_000_000)
            }
        ])

        let (events, handle) = await surface.beginStreamingExecution(plan: plan)
        executionHandle = handle

        for await event in events {
            switch event {
            case .progress(let progress):
                progressFraction = progress.fraction
                progressMessage = progress.message
            case .finished(let outcome):
                isExecuting = false
                executionHandle = nil
                switch outcome {
                case .success:
                    transcript.append(TranscriptEntry(
                        role: .assistant,
                        text: "Summary of “\(entity.displayName)”: three sections, two open decisions, one action item. (Simulated.)"
                    ))
                case .cancelled:
                    transcript.append(TranscriptEntry(role: .assistant, text: "Summary cancelled."))
                case .failure(let message):
                    transcript.append(TranscriptEntry(role: .assistant, text: "Summary failed: \(message)"))
                }
            }
        }
    }

    func cancelExecution() {
        executionHandle?.cancel()
    }

    private func describe(_ failure: SessionRefusal) -> String {
        switch failure {
        case .resolutionFailed(let reason):
            switch reason {
            case .emptyScreen:
                return "Nothing is on screen to act on."
            case .ordinalOutOfRange(let requested, let visible):
                return "You asked for item \(requested), but only \(visible) \(visible == 1 ? "is" : "are") visible."
            case .nothingFocused:
                return "Nothing is selected right now — tap a document or say its name."
            case .noMatch(let query):
                return "I couldn’t find anything called “\(query)”."
            case .belowConfidence(let query, _):
                return "Nothing matches “\(query)” closely enough to act safely."
            case .staleAnnotation:
                return "That item just changed on screen — please try again."
            }
        case .contextChanged:
            return "The screen changed, so I dropped that question. Ask again with what you see now."
        case .clarificationExpired:
            return "That question expired. Ask again when ready."
        }
    }

    private func spokenOrdinal(for index: Int) -> String {
        let words = ["first", "second", "third", "fourth", "fifth",
                     "sixth", "seventh", "eighth", "ninth", "tenth"]
        let arrayIndex = index - 1
        guard arrayIndex >= 0, arrayIndex < words.count else { return "\(index)th" }
        return words[arrayIndex]
    }
}

// MARK: - Views

struct ContentView: View {
    @State private var model = AppModel()
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                documentList
                Divider()
                assistantConsole
            }
            .navigationTitle("Intent Surface")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await model.start()
        }
    }

    private var documentList: some View {
        List {
            Section("On screen (annotated for the assistant)") {
                if model.documents.isEmpty {
                    Text("No documents left — everything was deleted.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(model.documents.enumerated()), id: \.element.id) { index, document in
                        DocumentRow(
                            document: document,
                            ordinal: index + 1,
                            isFocused: model.focusedDocumentID == document.id
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { model.tapped(document) }
                        .onAppear { model.rowAppeared(document) }
                        .onDisappear { model.rowDisappeared(document) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var assistantConsole: some View {
        VStack(alignment: .leading, spacing: 10) {
            transcriptView

            if !model.pendingCandidates.isEmpty {
                clarificationChips
            }

            if model.isExecuting {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(model.progressMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel") { model.cancelExecution() }
                            .font(.caption)
                    }
                    ProgressView(value: model.progressFraction)
                }
                .padding(.horizontal)
            }

            quickChips

            HStack {
                TextField("Say it — “share the third one”", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onSubmit { send() }
                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding([.horizontal, .bottom])
        }
        .padding(.top, 8)
        .background(.thinMaterial)
    }

    private var transcriptView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.transcript) { entry in
                        TranscriptRow(entry: entry)
                            .id(entry.id)
                    }
                }
                .padding(.horizontal)
            }
            .frame(height: 170)
            .onChange(of: model.transcript) { _, entries in
                if let last = entries.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var clarificationChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(Array(model.pendingCandidates.enumerated()), id: \.element.id) { index, candidate in
                    Button {
                        Task { await model.pickCandidate(at: index) }
                    } label: {
                        Text("\(index + 1). \(candidate.displayName)")
                            .font(.callout)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private var quickChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(
                    ["share the third one", "open the budget", "summarize this",
                     "open meeting notes", "delete the sixth one"],
                    id: \.self
                ) { suggestion in
                    Button {
                        Task { await model.submit(suggestion) }
                    } label: {
                        Text(suggestion)
                            .font(.callout)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().strokeBorder(.secondary.opacity(0.4)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    private func send() {
        let text = draft
        draft = ""
        Task { await model.submit(text) }
    }
}

struct DocumentRow: View {
    let document: DemoDocument
    let ordinal: Int
    let isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("\(ordinal)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Image(systemName: "doc.text")
                .foregroundStyle(isFocused ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading) {
                Text(document.name)
                Text(document.kind)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isFocused {
                Image(systemName: "scope")
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel("Focused for “this”")
            }
        }
        .padding(.vertical, 2)
    }
}

struct TranscriptRow: View {
    let entry: TranscriptEntry

    var body: some View {
        HStack {
            if entry.role == .user { Spacer(minLength: 40) }
            Text(entry.text)
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(bubbleColor, in: RoundedRectangle(cornerRadius: 14))
                .frame(maxWidth: .infinity, alignment: alignment)
            if entry.role != .user { Spacer(minLength: 40) }
        }
    }

    private var bubbleColor: Color {
        switch entry.role {
        case .user: return Color.accentColor.opacity(0.2)
        case .assistant: return Color.secondary.opacity(0.15)
        case .system: return Color.yellow.opacity(0.18)
        }
    }

    private var alignment: Alignment {
        entry.role == .user ? .trailing : .leading
    }
}

// MARK: - Entry point

@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
