import SwiftUI

struct MeetingDraft: Identifiable {
    var meeting: Meeting
    var isNew: Bool

    var id: String { meeting.id }
}

struct MeetingEditorView: View {
    @Environment(MeetingStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let isNew: Bool
    @State private var meeting: Meeting
    @State private var linkText: String
    @State private var errorMessage: String?

    init(draft: MeetingDraft) {
        isNew = draft.isNew
        _meeting = State(initialValue: draft.meeting)
        _linkText = State(initialValue: draft.meeting.url?.absoluteString ?? "")
    }

    private var trimmedTitle: String {
        meeting.title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var linkIsValid: Bool {
        linkText.trimmingCharacters(in: .whitespaces).isEmpty || Meeting.parseLink(linkText) != nil
    }

    var body: some View {
        let isEditable = store.isEditable(meeting)
        VStack(spacing: 0) {
            Form {
                TextField("Title", text: $meeting.title, prompt: Text("Meeting name"))
                DatePicker("Starts", selection: $meeting.start)
                DatePicker("Ends", selection: $meeting.end, in: meeting.start...)
                TextField("Meeting link", text: $linkText, prompt: Text("https://meet.google.com/…"))
                if !linkIsValid {
                    Text("Enter a valid URL.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if !isEditable, let provider = store.providerName(for: meeting) {
                    Text("This meeting is from \(provider) and can only be changed there.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .disabled(!isEditable)
            .onChange(of: meeting.start) { oldStart, newStart in
                // Keep the duration when moving the start.
                meeting.end = newStart + meeting.end.timeIntervalSince(oldStart)
            }

            HStack {
                if !isNew && isEditable {
                    Button("Delete", role: .destructive) { perform { try await store.delete(meeting) } }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save") {
                    meeting.title = trimmedTitle
                    meeting.url = Meeting.parseLink(linkText)
                    perform { try await store.save(meeting) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isEditable || trimmedTitle.isEmpty || !linkIsValid)
            }
            .padding()
        }
        .frame(width: 420)
    }

    private func perform(_ action: @escaping () async throws -> Void) {
        Task {
            do {
                try await action()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
